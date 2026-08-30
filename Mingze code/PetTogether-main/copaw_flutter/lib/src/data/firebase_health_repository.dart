import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as tz;
import '../domain/health_models.dart';
import 'firebase_health_gateway.dart';
import 'health_gateway.dart';
import 'health_mutation_store.dart';
import 'health_repository.dart';

final class FirebaseHealthRepository implements HealthRepository {
  FirebaseHealthRepository({
    HealthGateway? gateway,
    HealthMutationStore? mutationStore,
  }) : _gateway = gateway ?? FirebaseHealthGateway(),
       _mutationStore = mutationStore ?? SharedPreferencesHealthMutationStore();

  final HealthGateway _gateway;
  final HealthMutationStore _mutationStore;
  StreamSubscription<StoredHealthSnapshot>? _subscription;
  StreamController<HealthSnapshot>? _controller;
  int _generation = 0;

  @override
  Stream<HealthSnapshot> observeHealth(String householdId) {
    late final StreamController<HealthSnapshot> controller;
    controller = StreamController<HealthSnapshot>(
      onCancel: () => _cancelController(controller),
    );
    final generation = ++_generation;
    unawaited(_replaceObservation(householdId, controller, generation));
    return controller.stream;
  }

  Future<void> _replaceObservation(
    String householdId,
    StreamController<HealthSnapshot> controller,
    int generation,
  ) async {
    final previousSubscription = _subscription;
    final previousController = _controller;
    _subscription = null;
    _controller = controller;
    await previousSubscription?.cancel();
    if (previousController != null && previousController != controller) {
      await previousController.close();
    }
    if (generation != _generation || controller.isClosed) return;
    if (!_validId(householdId)) {
      controller.addError(
        const HealthRepositoryException(HealthRepositoryErrorCode.invalidInput),
      );
      await controller.close();
      return;
    }
    final subscription = _gateway
        .observeHealth(householdId)
        .listen(
          (snapshot) {
            if (generation != _generation || controller.isClosed) return;
            final records = <HealthRecord>[];
            var dropped = 0;
            for (final document in snapshot.documents.where(
              (document) => !document.hasPendingWrites,
            )) {
              try {
                records.add(_decode(document));
              } on Object {
                dropped += 1;
              }
            }
            controller.add(
              HealthSnapshot(
                List.unmodifiable(records),
                isFromCache: snapshot.isFromCache,
                droppedRecordCount: dropped,
              ),
            );
          },
          onError: (Object error) {
            if (generation == _generation && !controller.isClosed) {
              controller.addError(_mapped(error));
            }
          },
        );
    if (generation != _generation || controller.isClosed) {
      await subscription.cancel();
    } else {
      _subscription = subscription;
    }
  }

  @override
  Future<void> createRecord({
    required String householdId,
    required String petId,
    required String petName,
    required HealthRecordType type,
    required DateTime recordedAt,
    required String timeZoneIdentifier,
    required String? detail,
    required double? weightKilograms,
    double? waterMilliliters,
    DailyHealthCheckIn? dailyCheckIn,
    required String createdById,
    required String createdByName,
  }) async {
    final normalizedDetail = detail?.trim();
    final isWeight = type == HealthRecordType.weight;
    final isWater = type == HealthRecordType.waterIntake;
    final isDailyCheckIn = type == HealthRecordType.dailyCheckIn;
    final recordedLocalDate = _localDate(recordedAt, timeZoneIdentifier);
    if (!_validId(householdId) ||
        !_validId(petId) ||
        !_validText(petName, 60) ||
        !_validId(createdById) ||
        !_validText(createdByName, 50) ||
        recordedLocalDate == null ||
        recordedAt.isAfter(DateTime.now().add(const Duration(minutes: 1))) ||
        (normalizedDetail != null && normalizedDetail.length > 500) ||
        (isWeight &&
            (weightKilograms == null ||
                weightKilograms <= 0 ||
                weightKilograms > 500)) ||
        (isWeight && waterMilliliters != null) ||
        (isWater &&
            (waterMilliliters == null ||
                waterMilliliters <= 0 ||
                waterMilliliters > 10000 ||
                waterMilliliters != waterMilliliters.roundToDouble())) ||
        (isWater && weightKilograms != null) ||
        (isDailyCheckIn && dailyCheckIn == null) ||
        (isDailyCheckIn && weightKilograms != null) ||
        (isDailyCheckIn &&
            waterMilliliters != null &&
            (waterMilliliters <= 0 ||
                waterMilliliters > 10000 ||
                waterMilliliters != waterMilliliters.roundToDouble())) ||
        (!isDailyCheckIn && dailyCheckIn != null) ||
        (!isWeight &&
            !isWater &&
            !isDailyCheckIn &&
            (normalizedDetail == null || normalizedDetail.isEmpty)) ||
        (!isWeight &&
            !isWater &&
            !isDailyCheckIn &&
            (weightKilograms != null || waterMilliliters != null))) {
      throw const HealthRepositoryException(
        HealthRepositoryErrorCode.invalidInput,
      );
    }
    try {
      final requestHash = sha256
          .convert(
            utf8.encode(
              jsonEncode({
                'householdID': householdId,
                'petID': petId,
                'petName': petName.trim(),
                'type': type.name,
                'recordedAt': recordedAt.toUtc().toIso8601String(),
                'timeZoneIdentifier': timeZoneIdentifier,
                'detail': normalizedDetail,
                'weightKilograms': weightKilograms,
                'waterMilliliters': waterMilliliters,
                'waterLevel': dailyCheckIn?.water.name,
                'appetiteLevel': dailyCheckIn?.appetite.name,
                'urinationLevel': dailyCheckIn?.urination.name,
                'stoolStatus': dailyCheckIn?.stool.name,
                'energyLevel': dailyCheckIn?.energy.name,
                'moodStatus': dailyCheckIn?.mood.name,
                'createdByID': createdById,
                'createdByName': createdByName.trim(),
              }),
            ),
          )
          .toString();
      if (isDailyCheckIn) {
        final checkIn = dailyCheckIn!;
        await _gateway.createDailyCheckIn({
          'householdID': householdId,
          'petID': petId,
          'waterLevel': checkIn.water.name,
          'appetiteLevel': checkIn.appetite.name,
          'urinationLevel': checkIn.urination.name,
          'stoolStatus': checkIn.stool.name,
          'energyLevel': checkIn.energy.name,
          'moodStatus': checkIn.mood.name,
          'waterMilliliters': waterMilliliters?.round(),
          'detail': normalizedDetail?.isEmpty == true ? null : normalizedDetail,
          'clientMutationID': requestHash,
        });
        return;
      }
      final recordId = await _mutationStore.readOrCreate(
        requestHash,
        () => _gateway.newRecordId(householdId),
      );
      if (!_validId(recordId)) {
        throw const HealthRepositoryException(
          HealthRepositoryErrorCode.backendUnavailable,
        );
      }
      await _gateway.createRecord(
        CreateHealthRecordCommand(
          householdId: householdId,
          recordId: recordId,
          petId: petId,
          type: type.name,
          recordedAt: recordedAt,
          detail: normalizedDetail?.isEmpty == true ? null : normalizedDetail,
          weightKilograms: weightKilograms,
          waterMilliliters: waterMilliliters,
        ),
      );
      await _mutationStore.clear(requestHash);
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Future<void> stopObserving() async {
    _generation += 1;
    final subscription = _subscription;
    final controller = _controller;
    _subscription = null;
    _controller = null;
    await subscription?.cancel();
    await controller?.close();
  }

  Future<void> _cancelController(
    StreamController<HealthSnapshot> controller,
  ) async {
    if (!identical(_controller, controller)) return;
    await stopObserving();
  }

  static HealthRecord _decode(StoredHealthDocument document) {
    final data = document.data;
    final type = HealthRecordType.values
        .where((value) => value.name == data['type'])
        .firstOrNull;
    final recordedAt = data['recordedAt'];
    final createdAt = data['createdAt'];
    final petId = data['petID'];
    final petName = data['petName'];
    final actorId = data['createdByID'];
    final actorName = data['createdByName'];
    final detail = data['detail'];
    final weight = data['weightKilograms'];
    final water = data['waterMilliliters'];
    final dailyCheckIn = _decodeDailyCheckIn(data, type);
    final schemaVersion = data['schemaVersion'];
    final recordedLocalDate = data['recordedLocalDate'];
    final recordedTimeZoneIdentifier = data['recordedTimeZoneIdentifier'];
    final waterMeasurementBasis = _waterBasis(
      data['waterMeasurementBasis'],
      schemaVersion,
      water,
    );
    if ((schemaVersion != 1 && schemaVersion != 2) ||
        type == null ||
        petId is! String ||
        !_validId(petId) ||
        petName is! String ||
        !_validText(petName, 60) ||
        actorId is! String ||
        !_validId(actorId) ||
        actorName is! String ||
        !_validText(actorName, 50) ||
        recordedAt is! Timestamp ||
        createdAt is! Timestamp ||
        (schemaVersion == 2 &&
            (recordedLocalDate is! String ||
                !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(recordedLocalDate))) ||
        (schemaVersion == 2 &&
            (recordedTimeZoneIdentifier is! String ||
                recordedTimeZoneIdentifier.isEmpty)) ||
        recordedAt.toDate().isAfter(
          createdAt.toDate().add(const Duration(seconds: 5)),
        ) ||
        (type == HealthRecordType.weight &&
            (weight is! num || weight <= 0 || weight > 500)) ||
        (type == HealthRecordType.weight && water != null) ||
        (type == HealthRecordType.weight &&
            detail != null &&
            (detail is! String || detail.length > 500)) ||
        (type == HealthRecordType.waterIntake &&
            (water is! num || water <= 0 || water > 10000)) ||
        (schemaVersion == 2 &&
            type == HealthRecordType.waterIntake &&
            waterMeasurementBasis != WaterMeasurementBasis.singleIntake &&
            waterMeasurementBasis != WaterMeasurementBasis.fullLocalDay) ||
        (type == HealthRecordType.waterIntake && weight != null) ||
        (type == HealthRecordType.waterIntake &&
            detail != null &&
            (detail is! String || detail.length > 500)) ||
        (type == HealthRecordType.dailyCheckIn && dailyCheckIn == null) ||
        (type == HealthRecordType.dailyCheckIn && weight != null) ||
        (type == HealthRecordType.dailyCheckIn &&
            water != null &&
            (water is! num || water <= 0 || water > 10000)) ||
        (schemaVersion == 2 &&
            type == HealthRecordType.dailyCheckIn &&
            water != null &&
            waterMeasurementBasis != WaterMeasurementBasis.localDayToDate &&
            waterMeasurementBasis != WaterMeasurementBasis.fullLocalDay) ||
        (type == HealthRecordType.dailyCheckIn &&
            detail != null &&
            (detail is! String || detail.length > 500)) ||
        (type != HealthRecordType.dailyCheckIn && _hasDailyFields(data)) ||
        (type != HealthRecordType.weight &&
            type != HealthRecordType.waterIntake &&
            type != HealthRecordType.dailyCheckIn &&
            (weight != null || water != null)) ||
        (type != HealthRecordType.weight &&
            type != HealthRecordType.waterIntake &&
            type != HealthRecordType.dailyCheckIn &&
            (detail is! String || detail.isEmpty || detail.length > 500))) {
      throw const FormatException('Malformed health record');
    }
    return HealthRecord(
      id: document.id,
      petId: petId,
      petNameSnapshot: petName,
      type: type,
      recordedAt: recordedAt.toDate(),
      recordedLocalDate: recordedLocalDate as String?,
      recordedTimeZoneIdentifier: recordedTimeZoneIdentifier as String?,
      detail: detail as String?,
      weightKilograms: (weight as num?)?.toDouble(),
      waterMilliliters: (water as num?)?.toDouble(),
      waterMeasurementBasis: waterMeasurementBasis,
      dailyCheckIn: dailyCheckIn,
      createdById: actorId,
      createdByNameSnapshot: actorName,
      createdAt: createdAt.toDate(),
    );
  }

  static DailyHealthCheckIn? _decodeDailyCheckIn(
    Map<String, Object?> data,
    HealthRecordType? type,
  ) {
    final water = _enumByName(DailyHealthLevel.values, data['waterLevel']);
    final appetite = _enumByName(
      DailyHealthLevel.values,
      data['appetiteLevel'],
    );
    final urination = _enumByName(
      DailyHealthLevel.values,
      data['urinationLevel'],
    );
    final stool = _enumByName(DailyHealthStatus.values, data['stoolStatus']);
    final energy = _enumByName(DailyHealthLevel.values, data['energyLevel']);
    final mood = _enumByName(DailyHealthStatus.values, data['moodStatus']);
    if (type != HealthRecordType.dailyCheckIn) return null;
    if (water == null ||
        appetite == null ||
        urination == null ||
        stool == null ||
        energy == null ||
        mood == null) {
      return null;
    }
    return DailyHealthCheckIn(
      water: water,
      appetite: appetite,
      urination: urination,
      stool: stool,
      energy: energy,
      mood: mood,
    );
  }

  static bool _hasDailyFields(Map<String, Object?> data) => [
    data['waterLevel'],
    data['appetiteLevel'],
    data['urinationLevel'],
    data['stoolStatus'],
    data['energyLevel'],
    data['moodStatus'],
  ].any((value) => value != null);

  static WaterMeasurementBasis? _waterBasis(
    Object? value,
    Object? schemaVersion,
    Object? water,
  ) {
    if (water == null) return null;
    if (schemaVersion == 1) return WaterMeasurementBasis.legacyUnknown;
    return _enumByName(WaterMeasurementBasis.values, value);
  }

  static String? _localDate(DateTime instant, String identifier) {
    try {
      time_zone_data.initializeTimeZones();
      final local = tz.TZDateTime.from(instant, tz.getLocation(identifier));
      return '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
    } on Object {
      return null;
    }
  }

  static T? _enumByName<T extends Enum>(Iterable<T> values, Object? name) =>
      name is String
      ? values.where((value) => value.name == name).firstOrNull
      : null;

  static bool _validId(String value) =>
      value.isNotEmpty && value.length <= 128 && !value.contains('/');

  static bool _validText(String value, int maximum) =>
      value.trim().isNotEmpty && value.trim().length <= maximum;

  static HealthRepositoryException _mapped(Object error) {
    if (error is HealthRepositoryException) return error;
    if (error is FirebaseException) {
      return HealthRepositoryException(switch (error.code) {
        'unavailable' ||
        'network-request-failed' => HealthRepositoryErrorCode.network,
        'permission-denied' => HealthRepositoryErrorCode.permission,
        'already-exists' || 'aborted' => HealthRepositoryErrorCode.conflict,
        _ => HealthRepositoryErrorCode.backendUnavailable,
      }, diagnosticCode: error.code);
    }
    return const HealthRepositoryException(
      HealthRepositoryErrorCode.backendUnavailable,
    );
  }
}
