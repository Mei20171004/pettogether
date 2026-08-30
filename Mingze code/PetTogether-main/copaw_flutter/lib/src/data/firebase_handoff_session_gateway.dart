import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'handoff_session_gateway.dart';

final class FirebaseHandoffSessionGateway implements HandoffSessionGateway {
  FirebaseHandoffSessionGateway({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Stream<StoredHandoffSessionAuthority> observeAuthority(String householdId) {
    final household = _firestore.collection('households').doc(householdId);
    final pointer = household.collection('handoff').doc('sessionState');
    final sessions = household.collection('handoffSessions');
    final versions = household.collection('handoffVersions');
    late final StreamController<StoredHandoffSessionAuthority> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    pointerSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    sessionsSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    versionsSubscription;
    DocumentSnapshot<Map<String, dynamic>>? pointerSnapshot;
    QuerySnapshot<Map<String, dynamic>>? sessionsSnapshot;
    QuerySnapshot<Map<String, dynamic>>? versionsSnapshot;

    void emit() {
      final currentPointer = pointerSnapshot;
      final currentSessions = sessionsSnapshot;
      final currentVersions = versionsSnapshot;
      if (currentPointer == null ||
          currentSessions == null ||
          currentVersions == null) {
        return;
      }
      controller.add(
        StoredHandoffSessionAuthority(
          pointerExists: currentPointer.exists,
          pointerData:
              currentPointer.data()?.cast<String, Object?>() ?? const {},
          sessions: currentSessions.docs
              .map(
                (document) => StoredHandoffSessionDocument(
                  id: document.id,
                  data: document.data().cast<String, Object?>(),
                ),
              )
              .toList(growable: false),
          versions: currentVersions.docs
              .map(
                (document) => StoredHandoffVersionDocument(
                  id: document.id,
                  data: document.data().cast<String, Object?>(),
                ),
              )
              .toList(growable: false),
          isFromCache:
              currentPointer.metadata.isFromCache ||
              currentSessions.metadata.isFromCache ||
              currentVersions.metadata.isFromCache,
        ),
      );
    }

    controller = StreamController<StoredHandoffSessionAuthority>(
      onListen: () {
        pointerSubscription = pointer
            .snapshots(includeMetadataChanges: true)
            .listen((snapshot) {
              pointerSnapshot = snapshot;
              emit();
            }, onError: controller.addError);
        sessionsSubscription = sessions
            .snapshots(includeMetadataChanges: true)
            .listen((snapshot) {
              sessionsSnapshot = snapshot;
              emit();
            }, onError: controller.addError);
        versionsSubscription = versions
            .snapshots(includeMetadataChanges: true)
            .listen((snapshot) {
              versionsSnapshot = snapshot;
              emit();
            }, onError: controller.addError);
      },
      onCancel: () async {
        await pointerSubscription?.cancel();
        await sessionsSubscription?.cancel();
        await versionsSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<Map<String, Object?>> mutate(Map<String, Object?> payload) async {
    final response = await _functions
        .httpsCallable('mutateHandoffSession')
        .call(payload);
    if (response.data is! Map) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Unexpected handoff session response.',
      );
    }
    return Map<String, Object?>.from(response.data as Map);
  }
}
