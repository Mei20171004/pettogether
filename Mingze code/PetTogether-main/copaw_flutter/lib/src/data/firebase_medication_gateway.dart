import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'medication_gateway.dart';

final class FirebaseMedicationGateway implements MedicationGateway {
  FirebaseMedicationGateway({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _medications;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _occurrences;
  StreamController<MedicationGatewaySnapshot>? _controller;
  int _generation = 0;

  @override
  Stream<MedicationGatewaySnapshot> observe(String householdId) {
    final generation = ++_generation;
    late final StreamController<MedicationGatewaySnapshot> controller;
    controller = StreamController<MedicationGatewaySnapshot>(
      onCancel: () => _cancelGeneration(generation, controller),
    );
    unawaited(_replaceObservation(householdId, controller, generation));
    return controller.stream;
  }

  Future<void> _replaceObservation(
    String householdId,
    StreamController<MedicationGatewaySnapshot> controller,
    int generation,
  ) async {
    await _cancelCurrent();
    if (generation != _generation) {
      await controller.close();
      return;
    }
    _controller = controller;
    final household = _firestore.collection('households').doc(householdId);
    QuerySnapshot<Map<String, dynamic>>? medicationSnapshot;
    QuerySnapshot<Map<String, dynamic>>? occurrenceSnapshot;
    var loadingVersions = false;
    var reloadRequested = false;

    Future<void> emitIfReady() async {
      if (loadingVersions) {
        reloadRequested = true;
        return;
      }
      final medications = medicationSnapshot;
      final occurrences = occurrenceSnapshot;
      if (medications == null || occurrences == null) return;
      loadingVersions = true;
      do {
        reloadRequested = false;
        try {
          final versionQueries = await Future.wait(
            medications.docs.map(
              (document) => document.reference
                  .collection('scheduleVersions')
                  .orderBy('version')
                  .get(),
            ),
          );
          if (generation != _generation || controller.isClosed) return;
          controller.add(
            MedicationGatewaySnapshot(
              medications: medications.docs
                  .map(_stored)
                  .toList(growable: false),
              schedules: versionQueries
                  .expand((query) => query.docs)
                  .map(_stored)
                  .toList(growable: false),
              occurrences: occurrences.docs
                  .map(_stored)
                  .toList(growable: false),
              isFromCache:
                  medications.metadata.isFromCache ||
                  occurrences.metadata.isFromCache ||
                  versionQueries.any((item) => item.metadata.isFromCache),
              hasPendingWrites:
                  medications.metadata.hasPendingWrites ||
                  occurrences.metadata.hasPendingWrites ||
                  versionQueries.any((item) => item.metadata.hasPendingWrites),
            ),
          );
        } on Object catch (error, stackTrace) {
          if (generation == _generation && !controller.isClosed) {
            controller.addError(error, stackTrace);
          }
        }
      } while (reloadRequested && generation == _generation);
      loadingVersions = false;
    }

    void addError(Object error, StackTrace stackTrace) {
      if (generation == _generation && !controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }

    _medications = household
        .collection('medications')
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
          medicationSnapshot = snapshot;
          unawaited(emitIfReady());
        }, onError: addError);
    _occurrences = household
        .collection('medicationOccurrences')
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
          occurrenceSnapshot = snapshot;
          unawaited(emitIfReady());
        }, onError: addError);
  }

  @override
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> payload,
  ) async {
    final result = await _functions.httpsCallable(name).call(payload);
    if (result.data is! Map) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Unexpected medication response.',
      );
    }
    return Map<String, Object?>.from(result.data as Map);
  }

  @override
  Future<void> stopObserving() async {
    _generation += 1;
    await _cancelCurrent();
  }

  Future<void> _cancelCurrent() async {
    final medications = _medications;
    final occurrences = _occurrences;
    final controller = _controller;
    _medications = null;
    _occurrences = null;
    _controller = null;
    await medications?.cancel();
    await occurrences?.cancel();
    await controller?.close();
  }

  Future<void> _cancelGeneration(
    int generation,
    StreamController<MedicationGatewaySnapshot> controller,
  ) async {
    if (generation != _generation) return;
    _generation += 1;
    if (!identical(_controller, controller)) return;
    final medications = _medications;
    final occurrences = _occurrences;
    _medications = null;
    _occurrences = null;
    _controller = null;
    await medications?.cancel();
    await occurrences?.cancel();
  }

  static MedicationStoredDocument _stored(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => MedicationStoredDocument(
    id: snapshot.id,
    data: snapshot.data()?.cast<String, Object?>() ?? const {},
  );
}
