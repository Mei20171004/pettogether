import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'task_responsibility_gateway.dart';

final class FirebaseTaskResponsibilityGateway
    implements TaskResponsibilityGateway {
  FirebaseTaskResponsibilityGateway({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Stream<StoredResponsibilityTransferSnapshot> observeTransfers(
    String householdId,
  ) {
    final household = _firestore.collection('households').doc(householdId);
    final transfers = household.collection('taskResponsibilityTransfers');
    final pointers = household.collection('taskResponsibilityState');
    late final StreamController<StoredResponsibilityTransferSnapshot>
    controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    transferSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    pointerSubscription;
    QuerySnapshot<Map<String, dynamic>>? transferSnapshot;
    QuerySnapshot<Map<String, dynamic>>? pointerSnapshot;

    void emit() {
      final currentTransfers = transferSnapshot;
      final currentPointers = pointerSnapshot;
      if (currentTransfers == null || currentPointers == null) return;
      controller.add(
        StoredResponsibilityTransferSnapshot(
          documents: currentTransfers.docs
              .map(
                (document) => StoredResponsibilityTransferDocument(
                  id: document.id,
                  data: document.data().cast<String, Object?>(),
                ),
              )
              .toList(growable: false),
          pointers: currentPointers.docs
              .map(
                (document) => StoredResponsibilityPointerDocument(
                  id: document.id,
                  data: document.data().cast<String, Object?>(),
                ),
              )
              .toList(growable: false),
          isFromCache:
              currentTransfers.metadata.isFromCache ||
              currentPointers.metadata.isFromCache,
        ),
      );
    }

    controller = StreamController(
      onListen: () {
        transferSubscription = transfers
            .snapshots(includeMetadataChanges: true)
            .listen((snapshot) {
              transferSnapshot = snapshot;
              emit();
            }, onError: controller.addError);
        pointerSubscription = pointers
            .snapshots(includeMetadataChanges: true)
            .listen((snapshot) {
              pointerSnapshot = snapshot;
              emit();
            }, onError: controller.addError);
      },
      onCancel: () async {
        await transferSubscription?.cancel();
        await pointerSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<Map<String, Object?>> mutate(Map<String, Object?> payload) async {
    final response = await _functions
        .httpsCallable('mutateTaskResponsibility')
        .call(payload);
    if (response.data is! Map) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Unexpected responsibility response.',
      );
    }
    return Map<String, Object?>.from(response.data as Map);
  }
}
