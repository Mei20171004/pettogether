import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/handoff_models.dart';
import 'firebase_handoff_gateway.dart';
import 'handoff_gateway.dart';
import 'handoff_repository.dart';

final class FirebaseHandoffRepository implements HandoffRepository {
  FirebaseHandoffRepository({HandoffGateway? gateway})
    : _gateway = gateway ?? FirebaseHandoffGateway();

  static const _keys = {
    'schemaVersion',
    'careInstructions',
    'emergencyContactName',
    'emergencyContactPhone',
    'veterinaryHospitalName',
    'veterinaryHospitalPhone',
    'revision',
    'updatedByID',
    'updatedByName',
    'updatedAt',
  };

  final HandoffGateway _gateway;
  StreamSubscription<StoredHandoffDocument>? _subscription;
  StreamController<HandoffSnapshot>? _controller;
  int _generation = 0;

  @override
  Stream<HandoffSnapshot> observeHandoff(String householdId) {
    late final StreamController<HandoffSnapshot> controller;
    controller = StreamController<HandoffSnapshot>(
      onCancel: () => _cancelController(controller),
    );
    unawaited(_replaceObservation(householdId, controller));
    return controller.stream;
  }

  Future<void> _replaceObservation(
    String householdId,
    StreamController<HandoffSnapshot> controller,
  ) async {
    await stopObserving();
    final generation = ++_generation;
    _controller = controller;
    if (!_validId(householdId)) {
      controller.addError(
        const HandoffRepositoryException(
          HandoffRepositoryErrorCode.invalidInput,
        ),
      );
      await controller.close();
      return;
    }
    final subscription = _gateway
        .observeHandoff(householdId)
        .listen(
          (document) {
            if (generation != _generation || controller.isClosed) return;
            try {
              controller.add(
                HandoffSnapshot(
                  handoff: document.exists ? _decode(document.data) : null,
                  isFromCache: document.isFromCache,
                  hasPendingWrites: document.hasPendingWrites,
                ),
              );
            } on Object {
              controller.addError(
                const HandoffRepositoryException(
                  HandoffRepositoryErrorCode.malformedData,
                ),
              );
            }
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
  Future<void> saveHandoff({
    required String householdId,
    required int? expectedRevision,
    required String careInstructions,
    required String emergencyContactName,
    required String emergencyContactPhone,
    required String veterinaryHospitalName,
    required String veterinaryHospitalPhone,
    required String updatedById,
    required String updatedByName,
  }) async {
    final normalized = [
      careInstructions.trim(),
      emergencyContactName.trim(),
      emergencyContactPhone.trim(),
      veterinaryHospitalName.trim(),
      veterinaryHospitalPhone.trim(),
    ];
    if (!_validId(householdId) ||
        (expectedRevision != null && expectedRevision < 1) ||
        !_validId(updatedById) ||
        !_validText(updatedByName, 50) ||
        normalized[0].length > 1000 ||
        normalized[1].length > 80 ||
        normalized[2].length > 40 ||
        normalized[3].length > 100 ||
        normalized[4].length > 40) {
      throw const HandoffRepositoryException(
        HandoffRepositoryErrorCode.invalidInput,
      );
    }
    try {
      await _gateway.saveHandoff(
        SaveHandoffCommand(
          householdId: householdId,
          expectedRevision: expectedRevision,
          careInstructions: normalized[0],
          emergencyContactName: normalized[1],
          emergencyContactPhone: normalized[2],
          veterinaryHospitalName: normalized[3],
          veterinaryHospitalPhone: normalized[4],
          updatedById: updatedById,
          updatedByName: updatedByName.trim(),
        ),
      );
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
    StreamController<HandoffSnapshot> controller,
  ) async {
    if (identical(_controller, controller)) await stopObserving();
  }

  static HouseholdHandoff _decode(Map<String, Object?> data) {
    final care = data['careInstructions'];
    final contactName = data['emergencyContactName'];
    final contactPhone = data['emergencyContactPhone'];
    final hospitalName = data['veterinaryHospitalName'];
    final hospitalPhone = data['veterinaryHospitalPhone'];
    final revision = data['revision'];
    final actorId = data['updatedByID'];
    final actorName = data['updatedByName'];
    final updatedAt = data['updatedAt'];
    if (data.keys.toSet().difference(_keys).isNotEmpty ||
        data['schemaVersion'] != 1 ||
        care is! String ||
        care.length > 1000 ||
        contactName is! String ||
        contactName.length > 80 ||
        contactPhone is! String ||
        contactPhone.length > 40 ||
        hospitalName is! String ||
        hospitalName.length > 100 ||
        hospitalPhone is! String ||
        hospitalPhone.length > 40 ||
        revision is! int ||
        revision < 1 ||
        actorId is! String ||
        !_validId(actorId) ||
        actorName is! String ||
        !_validText(actorName, 50) ||
        updatedAt is! Timestamp) {
      throw const FormatException('Malformed handoff document');
    }
    return HouseholdHandoff(
      careInstructions: care,
      emergencyContactName: contactName,
      emergencyContactPhone: contactPhone,
      veterinaryHospitalName: hospitalName,
      veterinaryHospitalPhone: hospitalPhone,
      revision: revision,
      updatedById: actorId,
      updatedByNameSnapshot: actorName,
      updatedAt: updatedAt.toDate(),
    );
  }

  static bool _validId(String value) =>
      value.isNotEmpty && value.length <= 128 && !value.contains('/');

  static bool _validText(String value, int maximum) =>
      value.trim().isNotEmpty && value.trim().length <= maximum;

  static HandoffRepositoryException _mapped(Object error) {
    if (error is HandoffRepositoryException) return error;
    if (error is HandoffRevisionConflict) {
      return const HandoffRepositoryException(
        HandoffRepositoryErrorCode.conflict,
      );
    }
    if (error is FirebaseException) {
      return HandoffRepositoryException(switch (error.code) {
        'unavailable' ||
        'network-request-failed' => HandoffRepositoryErrorCode.network,
        'permission-denied' => HandoffRepositoryErrorCode.permission,
        _ => HandoffRepositoryErrorCode.backendUnavailable,
      }, diagnosticCode: error.code);
    }
    return const HandoffRepositoryException(
      HandoffRepositoryErrorCode.backendUnavailable,
    );
  }
}
