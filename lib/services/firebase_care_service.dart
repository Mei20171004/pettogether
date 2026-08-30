import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/health.dart';
import '../models/models.dart';
import '../utils/extensions.dart';
import '../utils/id.dart';
import 'care_service.dart';

/// Firestore-backed [CareService], ported from `FirebaseCareService.swift` and
/// `FirebaseModels.swift`. Reads and writes the same document shape and the
/// same flattened assignment-request fields, so it interoperates with the
/// original app and its security rules.
class FirebaseCareService implements CareService {
  static const _householdIDKey = 'pettogether.activeHouseholdID';

  StreamSubscription? _householdSub;
  StreamSubscription? _taskSub;
  StreamSubscription? _caregiverSub;
  StreamSubscription? _routineSub;
  StreamSubscription? _medicationPlanSub;
  StreamSubscription? _healthRecordSub;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // -------------------------------------------------------------------------
  // Session
  // -------------------------------------------------------------------------

  @override
  Future<CareSession?> restoreSession() async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    final householdID = await _savedHouseholdID();
    if (householdID != null) {
      // The saved id may belong to a previous account on this device. Reading
      // it then throws permission-denied — treat that as a stale cache and
      // fall through to the membership lookup instead of surfacing an error.
      try {
        final householdDoc = await _householdRef(householdID).get();
        final memberDoc = await _memberRef(householdID, user.uid).get();
        if (householdDoc.exists && memberDoc.exists) {
          return CareSession(
            household: _householdFrom(householdDoc),
            caregiver: _caregiverFrom(memberDoc),
          );
        }
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied') rethrow;
      }
      await _clearSavedHouseholdID();
    }

    // Fallback: the owner may have approved our join request while we were
    // offline. Collection-group lookup by the member `id` field finds the
    // household without knowing its id.
    final membership = await _db
        .collectionGroup('members')
        .where('id', isEqualTo: user.uid)
        .limit(1)
        .get();
    if (membership.docs.isNotEmpty) {
      final memberDoc = membership.docs.first;
      final resolvedHouseholdID = memberDoc.reference.parent.parent?.id;
      if (resolvedHouseholdID != null) {
        final householdDoc = await _householdRef(resolvedHouseholdID).get();
        if (householdDoc.exists) {
          await _saveHouseholdID(resolvedHouseholdID);
          return CareSession(
            household: _householdFrom(householdDoc),
            caregiver: _caregiverFrom(memberDoc),
          );
        }
      }
    }
    return null;
  }

  @override
  Future<CareSession> createHousehold({
    required String name,
    required List<Pet> pets,
    required String caregiverName,
  }) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    final householdRef = _db.collection('households').doc();
    final timeZoneIdentifier = DateTime.now().timeZoneName;
    final memberRef = householdRef.collection('members').doc(user.uid);

    await _db.runTransaction((tx) async {
      tx.set(
        householdRef,
        _householdData(
          id: householdRef.id,
          name: name,
          pets: pets,
          timeZoneIdentifier: timeZoneIdentifier,
          ownerID: user.uid,
        ),
      );
      tx.set(
        memberRef,
        _caregiverData(
          id: user.uid,
          displayName: caregiverName,
          role: 'owner',
        ),
      );
    });

    await _saveHouseholdID(householdRef.id);
    return CareSession(
      household: Household(
        id: householdRef.id,
        name: name,
        inviteCode: '',
        pets: pets,
        timeZoneIdentifier: timeZoneIdentifier,
        ownerID: user.uid,
      ),
      caregiver: Caregiver(id: user.uid, displayName: caregiverName),
    );
  }

  // -------------------------------------------------------------------------
  // Observers
  // -------------------------------------------------------------------------

  @override
  void observeHousehold({
    required String householdID,
    required void Function(Household) onChange,
    required void Function(Object error) onError,
  }) {
    _householdSub?.cancel();
    _householdSub = _householdRef(householdID).snapshots().listen(
          (snapshot) {
            if (!snapshot.exists) {
              onError(
                  const CareServiceError(CareServiceErrorType.householdMismatch));
              return;
            }
            onChange(_householdFrom(snapshot));
          },
          onError: (Object e) => onError(_map(e)),
        );
  }

  @override
  void observeTasks({
    required String householdID,
    required void Function(List<CareTask>) onChange,
    required void Function(Object error) onError,
  }) {
    _taskSub?.cancel();
    _taskSub = _householdRef(householdID)
        .collection('tasks')
        // Metadata matters for medication: a completion read from cache or
        // still being written must not be presented as a confirmed dose.
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            final confirmed = !snapshot.metadata.isFromCache &&
                !snapshot.metadata.hasPendingWrites;
            onChange(snapshot.docs
                .map((doc) => _taskFrom(
                      doc,
                      isServerConfirmed:
                          confirmed && !doc.metadata.hasPendingWrites,
                    ))
                .toList(growable: false));
          },
          onError: (Object e) => onError(_map(e)),
        );
  }

  @override
  void observeCaregivers({
    required String householdID,
    required void Function(List<Caregiver>) onChange,
    required void Function(Object error) onError,
  }) {
    _caregiverSub?.cancel();
    _caregiverSub = _householdRef(householdID)
        .collection('members')
        .snapshots()
        .listen(
          (snapshot) => onChange(
              snapshot.docs.map(_caregiverFrom).toList(growable: false)),
          onError: (Object e) => onError(_map(e)),
        );
  }

  @override
  void observeRoutines({
    required String householdID,
    required void Function(List<CareRoutine>) onChange,
    required void Function(Object error) onError,
  }) {
    _routineSub?.cancel();
    _routineSub = _householdRef(householdID)
        .collection('routines')
        .snapshots()
        .listen(
          (snapshot) => onChange(
              snapshot.docs.map(_routineFrom).toList(growable: false)),
          onError: (Object e) => onError(_map(e)),
        );
  }

  // -------------------------------------------------------------------------
  // Creates
  // -------------------------------------------------------------------------

  @override
  Future<void> addTask(CareTask task, String householdID) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    if (task.kind != CareTaskKind.oneOff ||
        task.status != CareTaskStatus.unclaimed ||
        task.createdByID != user.uid) {
      throw const CareServiceError(CareServiceErrorType.invalidTransition);
    }
    await _taskRef(householdID, task.id).set(
      _taskData(task, createdByID: user.uid, useServerCreatedAt: true),
    );
  }

  @override
  Future<void> updateRoutine(CareRoutine routine, String householdID) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    await _routineRef(householdID, routine.id).set(_routineData(routine));
  }

  @override
  Future<void> deleteRoutine(String routineID, String householdID) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    await _routineRef(householdID, routineID).delete();
  }

  @override
  Future<void> addRoutine(CareRoutine routine, String householdID) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    if (routine.createdByID != user.uid) {
      throw const CareServiceError(CareServiceErrorType.notHouseholdMember);
    }
    await _routineRef(householdID, routine.id).set(_routineData(routine));
  }

  @override
  Future<void> updateProfile(Household household, Caregiver caregiver) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    _validate(caregiver, user.uid);

    final householdName = household.name.trim();
    final petName = household.petName.trim();
    final caregiverName = caregiver.displayName.trim();
    if (householdName.isEmpty ||
        householdName.length > 60 ||
        petName.isEmpty ||
        petName.length > 60 ||
        caregiverName.isEmpty ||
        caregiverName.length > 50) {
      throw const CareServiceError(CareServiceErrorType.invalidProfile);
    }

    final batch = _db.batch();
    batch.update(_householdRef(household.id), {
      'name': householdName,
      'pets': household.pets.map((e) => e.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_memberRef(household.id, user.uid), {
      'displayName': caregiverName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  @override
  Future<void> addPet(String householdID, Pet pet) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    await _db.runTransaction((tx) async {
      final ref = _householdRef(householdID);
      final doc = await tx.get(ref);
      final pets = _petsFromData(doc.data())..add(pet);
      tx.update(ref, {'pets': pets.map((e) => e.toJson()).toList()});
    });
  }

  @override
  Future<void> updatePet(String householdID, Pet pet) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    await _db.runTransaction((tx) async {
      final ref = _householdRef(householdID);
      final doc = await tx.get(ref);
      final pets = [
        for (final p in _petsFromData(doc.data())) p.id == pet.id ? pet : p,
      ];
      tx.update(ref, {'pets': pets.map((e) => e.toJson()).toList()});
    });
  }

  @override
  Future<void> removePet(String householdID, String petID) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    await _db.runTransaction((tx) async {
      final ref = _householdRef(householdID);
      final doc = await tx.get(ref);
      final pets = _petsFromData(doc.data())
          .where((p) => p.id != petID)
          .toList();
      tx.update(ref, {'pets': pets.map((e) => e.toJson()).toList()});
    });
  }

  // -------------------------------------------------------------------------
  // Task mutations
  // -------------------------------------------------------------------------

  @override
  Future<void> claimTask(
    CareTask task,
    String householdID,
    Caregiver caregiver,
  ) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    _validate(caregiver, user.uid);
    final ref = _taskRef(householdID, task.id);

    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (doc.exists) {
        final data = doc.data()!;
        _requireUnclaimed(data);
        final update = <String, dynamic>{
          'status': CareTaskStatus.claimed.rawValue,
          'assigneeID': user.uid,
          'assigneeName': caregiver.displayName,
          'claimedAt': FieldValue.serverTimestamp(),
          'revision': _revision(data) + 1,
          ..._clearedRequest(),
        };
        tx.update(ref, update);
      } else {
        if (task.kind != CareTaskKind.routine || task.createdByID == null) {
          throw const CareServiceError(CareServiceErrorType.taskNotFound);
        }
        final materialized = task.copyWith(
          status: CareTaskStatus.claimed,
          clearAssignmentRequest: true,
          assigneeID: user.uid,
          assigneeNameSnapshot: caregiver.displayName,
          revision: task.revision + 1,
        );
        final payload = _taskData(
          materialized,
          createdByID: task.createdByID!,
          useServerCreatedAt: false,
        );
        payload['claimedAt'] = FieldValue.serverTimestamp();
        tx.set(ref, payload);
      }
    });
  }

  @override
  Future<void> requestAssignment(
    CareTask task,
    String householdID,
    Caregiver requester,
    Caregiver requestedCaregiver,
  ) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    _validate(requester, user.uid);
    if (requester.id == requestedCaregiver.id) {
      throw const CareServiceError(CareServiceErrorType.cannotRequestSelf);
    }

    final ref = _taskRef(householdID, task.id);
    final requesterRef = _memberRef(householdID, user.uid);
    final recipientRef = _memberRef(householdID, requestedCaregiver.id);
    final requestID = uuid();

    await _db.runTransaction((tx) async {
      final requesterDoc = await tx.get(requesterRef);
      final recipientDoc = await tx.get(recipientRef);
      final taskDoc = await tx.get(ref);

      final requesterName = requesterDoc.data()?['displayName'] as String?;
      if (!requesterDoc.exists || requesterName == null) {
        throw const CareServiceError(CareServiceErrorType.notHouseholdMember);
      }
      final recipientName = recipientDoc.data()?['displayName'] as String?;
      if (!recipientDoc.exists || recipientName == null) {
        throw const CareServiceError(CareServiceErrorType.caregiverNotFound);
      }

      final requestData = <String, dynamic>{
        'assignmentRequestID': requestID,
        'assignmentMode': AssignmentMode.direct.rawValue,
        'requestedByID': user.uid,
        'requestedByName': requesterName,
        'requestedToID': requestedCaregiver.id,
        'requestedToName': recipientName,
        'assignmentRequestedAt': FieldValue.serverTimestamp(),
      };

      if (taskDoc.exists) {
        final data = taskDoc.data()!;
        _requireUnclaimed(data);
        if (data['assignmentRequestID'] != null) {
          throw const CareServiceError(
              CareServiceErrorType.assignmentRequestChanged);
        }
        tx.update(ref, {
          ...requestData,
          'revision': _revision(data) + 1,
        });
      } else {
        if (task.kind != CareTaskKind.routine || task.createdByID == null) {
          throw const CareServiceError(CareServiceErrorType.taskNotFound);
        }
        final materialized = task.copyWith(
          assignmentRequest: AssignmentRequest(
            id: requestID,
            requestedByID: user.uid,
            requestedByNameSnapshot: requesterName,
            requestedToID: requestedCaregiver.id,
            requestedToNameSnapshot: recipientName,
            createdAt: DateTime.now(),
          ),
          revision: task.revision + 1,
        );
        final payload = _taskData(
          materialized,
          createdByID: task.createdByID!,
          useServerCreatedAt: false,
        );
        payload['assignmentRequestedAt'] = FieldValue.serverTimestamp();
        tx.set(ref, payload);
      }
    });
  }

  @override
  Future<void> requestOpenAssignment(
    CareTask task,
    String householdID,
    Caregiver requester,
  ) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    _validate(requester, user.uid);

    final ref = _taskRef(householdID, task.id);
    final requesterRef = _memberRef(householdID, user.uid);
    final requestID = uuid();

    await _db.runTransaction((tx) async {
      final requesterDoc = await tx.get(requesterRef);
      final taskDoc = await tx.get(ref);

      final requesterName = requesterDoc.data()?['displayName'] as String?;
      if (!requesterDoc.exists || requesterName == null) {
        throw const CareServiceError(CareServiceErrorType.notHouseholdMember);
      }

      final requestData = <String, dynamic>{
        'assignmentRequestID': requestID,
        'assignmentMode': AssignmentMode.open.rawValue,
        'requestedByID': user.uid,
        'requestedByName': requesterName,
        'requestedToID': FieldValue.delete(),
        'requestedToName': FieldValue.delete(),
        'assignmentRequestedAt': FieldValue.serverTimestamp(),
      };

      if (taskDoc.exists) {
        final data = taskDoc.data()!;
        _requireUnclaimed(data);
        if (data['assignmentRequestID'] != null) {
          throw const CareServiceError(
              CareServiceErrorType.assignmentRequestChanged);
        }
        tx.update(ref, {
          ...requestData,
          'revision': _revision(data) + 1,
        });
      } else {
        if (task.kind != CareTaskKind.routine || task.createdByID == null) {
          throw const CareServiceError(CareServiceErrorType.taskNotFound);
        }
        final materialized = task.copyWith(
          assignmentRequest: AssignmentRequest(
            id: requestID,
            requestedByID: user.uid,
            requestedByNameSnapshot: requesterName,
            mode: AssignmentMode.open,
            createdAt: DateTime.now(),
          ),
          revision: task.revision + 1,
        );
        final payload = _taskData(
          materialized,
          createdByID: task.createdByID!,
          useServerCreatedAt: false,
        );
        payload['assignmentRequestedAt'] = FieldValue.serverTimestamp();
        tx.set(ref, payload);
      }
    });
  }

  @override
  Future<void> acceptAssignmentRequest(
    String taskID,
    String requestID,
    String householdID,
    Caregiver caregiver,
  ) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    _validate(caregiver, user.uid);

    await _mutateRequest(_taskRef(householdID, taskID), (data) {
      _requireMatchingRequest(data, requestID);
      if ((data['requestedToID'] as String?) != user.uid) {
        throw const CareServiceError(CareServiceErrorType.notRequestRecipient);
      }
      return <String, dynamic>{
        'status': CareTaskStatus.claimed.rawValue,
        'assigneeID': user.uid,
        'assigneeName': caregiver.displayName,
        'claimedAt': FieldValue.serverTimestamp(),
        'revision': _revision(data) + 1,
        ..._clearedRequest(),
      };
    });
  }

  @override
  Future<void> declineAssignmentRequest(
    String taskID,
    String requestID,
    String householdID,
    Caregiver caregiver,
  ) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    _validate(caregiver, user.uid);

    await _mutateRequest(_taskRef(householdID, taskID), (data) {
      _requireMatchingRequest(data, requestID);
      if ((data['requestedToID'] as String?) != user.uid) {
        throw const CareServiceError(CareServiceErrorType.notRequestRecipient);
      }
      return {
        ..._clearedRequest(),
        'revision': _revision(data) + 1,
      };
    });
  }

  @override
  Future<void> cancelAssignmentRequest(
    String taskID,
    String requestID,
    String householdID,
    Caregiver caregiver,
  ) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    _validate(caregiver, user.uid);

    await _mutateRequest(_taskRef(householdID, taskID), (data) {
      _requireMatchingRequest(data, requestID);
      if ((data['requestedByID'] as String?) != user.uid) {
        throw const CareServiceError(CareServiceErrorType.notRequestOwner);
      }
      return {
        ..._clearedRequest(),
        'revision': _revision(data) + 1,
      };
    });
  }

  @override
  Future<void> completeTask(
    String taskID,
    String householdID,
    Caregiver caregiver,
  ) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    _validate(caregiver, user.uid);
    final ref = _taskRef(householdID, taskID);

    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) {
        throw const CareServiceError(CareServiceErrorType.taskNotFound);
      }
      final data = doc.data()!;
      final status = _status(data['status'] as String?);
      if (status == CareTaskStatus.completed) {
        throw const CareServiceError(CareServiceErrorType.taskAlreadyCompleted);
      }
      if (status != CareTaskStatus.claimed) {
        throw const CareServiceError(CareServiceErrorType.taskNotClaimed);
      }
      if ((data['assigneeID'] as String?) != user.uid) {
        throw const CareServiceError(CareServiceErrorType.notAssignee);
      }

      tx.update(ref, {
        'status': CareTaskStatus.completed.rawValue,
        'completedBy': caregiver.displayName,
        'completedByID': user.uid,
        'completedAt': FieldValue.serverTimestamp(),
        'revision': _revision(data) + 1,
      });
    });
  }

  @override
  Future<void> skipTaskOccurrence(
    CareTask task,
    String householdID,
    Caregiver caregiver, {
    MedicationSkipReason? reason,
    String? note,
  }) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    _validate(caregiver, user.uid);
    if (task.routineID == null) {
      throw const CareServiceError(CareServiceErrorType.invalidTransition);
    }
    final ref = _taskRef(householdID, task.id);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (doc.exists) {
        final data = doc.data()!;
        tx.update(ref, {
          'status': CareTaskStatus.skipped.rawValue,
          'skippedBy': caregiver.displayName,
          'skippedAt': FieldValue.serverTimestamp(),
          'skipReason': reason?.rawValue,
          'skipNote': note,
          'revision': _revision(data) + 1,
        });
      } else {
        if (task.createdByID == null) {
          throw const CareServiceError(CareServiceErrorType.taskNotFound);
        }
        final materialized = task.copyWith(
          status: CareTaskStatus.skipped,
          clearAssignmentRequest: true,
          skipReason: reason,
          skipNote: note,
          revision: task.revision + 1,
        );
        final payload = _taskData(
          materialized,
          createdByID: task.createdByID!,
          useServerCreatedAt: false,
        );
        payload['skippedBy'] = caregiver.displayName;
        payload['skippedAt'] = FieldValue.serverTimestamp();
        tx.set(ref, payload);
      }
    });
  }

  @override
  Future<void> restoreTaskOccurrence(
    CareTask task,
    String householdID,
    Caregiver caregiver,
  ) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    _validate(caregiver, user.uid);
    if (task.routineID == null) {
      throw const CareServiceError(CareServiceErrorType.invalidTransition);
    }
    final ref = _taskRef(householdID, task.id);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) {
        throw const CareServiceError(CareServiceErrorType.taskNotFound);
      }
      if (_status(doc.data()!['status'] as String?) != CareTaskStatus.skipped) {
        throw const CareServiceError(CareServiceErrorType.invalidTransition);
      }
      // Deleting the override lets the store regenerate the occurrence from
      // its routine (unclaimed), which also clears any skip reason.
      tx.delete(ref);
    });
  }

  // -------------------------------------------------------------------------
  // Invitations (one-time 24h link/QR + owner approval)
  // -------------------------------------------------------------------------

  @override
  Future<HouseholdInvitation> createInvitation({
    required String householdID,
    required String inviterName,
  }) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    final householdDoc = await _householdRef(householdID).get();
    final data = householdDoc.data();
    if (!householdDoc.exists || data == null) {
      throw const CareServiceError(CareServiceErrorType.householdMismatch);
    }
    if (data['ownerID'] != user.uid) {
      throw const CareServiceError(CareServiceErrorType.notOwner);
    }
    final ref = _db.collection('invitations').doc();
    final now = DateTime.now();
    final invitation = HouseholdInvitation(
      id: ref.id,
      householdId: householdID,
      householdName: data['name'] as String? ?? '',
      petNames: _petsFromData(data).map((p) => p.name).toList(),
      inviterName: inviterName,
      invitedBy: user.uid,
      status: InvitationStatus.active,
      createdAt: now,
      // Slightly under the rules' 24h ceiling: a client clock that runs a few
      // seconds fast would otherwise make `expiresAt <= request.time + 24h`
      // fail server-side and reject every invitation with permission-denied.
      expiresAt: now.add(const Duration(hours: 23, minutes: 55)),
    );
    final payload = invitation.toJson();
    payload['createdAt'] = Timestamp.fromDate(invitation.createdAt);
    payload['expiresAt'] = Timestamp.fromDate(invitation.expiresAt);
    await ref.set(payload);
    await _householdRef(householdID).update({'activeInvitationID': ref.id});
    return invitation;
  }

  @override
  Future<HouseholdInvitation> loadInvitation(String invitationID) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    final doc = await _db.collection('invitations').doc(invitationID).get();
    if (!doc.exists) {
      throw const CareServiceError(CareServiceErrorType.invitationNotFound);
    }
    final invitation = _invitationFrom(doc);
    if (invitation.status == InvitationStatus.revoked) {
      throw const CareServiceError(CareServiceErrorType.invitationRevoked);
    }
    if (invitation.status != InvitationStatus.active) {
      throw const CareServiceError(CareServiceErrorType.invitationAlreadyClaimed);
    }
    if (!invitation.expiresAt.isAfter(DateTime.now())) {
      throw const CareServiceError(CareServiceErrorType.invitationExpired);
    }
    return invitation;
  }

  @override
  Future<void> revokeInvitation(String invitationID) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    final ref = _db.collection('invitations').doc(invitationID);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) {
        throw const CareServiceError(CareServiceErrorType.invitationNotFound);
      }
      if (doc.data()!['invitedBy'] != user.uid) {
        throw const CareServiceError(CareServiceErrorType.notOwner);
      }
      tx.update(ref, {
        'status': InvitationStatus.revoked.rawValue,
        'revokedAt': FieldValue.serverTimestamp(),
      });
      tx.update(_householdRef(doc.data()!['householdId'] as String), {
        'activeInvitationID': FieldValue.delete(),
      });
    });
  }

  @override
  Future<HouseholdJoinRequest> requestToJoin({
    required HouseholdInvitation invitation,
    required String name,
    String? email,
  }) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    final invitationRef = _db.collection('invitations').doc(invitation.id);
    final requestRef = _householdRef(invitation.householdId)
        .collection('joinRequests')
        .doc(user.uid);
    final memberRef = _memberRef(invitation.householdId, user.uid);
    final now = DateTime.now();

    await _db.runTransaction((tx) async {
      final memberDoc = await tx.get(memberRef);
      if (memberDoc.exists) {
        throw const CareServiceError(CareServiceErrorType.alreadyMember);
      }
      final invitationDoc = await tx.get(invitationRef);
      if (!invitationDoc.exists) {
        throw const CareServiceError(CareServiceErrorType.invitationNotFound);
      }
      final data = invitationDoc.data()!;
      if (data['status'] != InvitationStatus.active.rawValue) {
        throw const CareServiceError(CareServiceErrorType.invitationAlreadyClaimed);
      }
      final expiresAt = _anyDate(data['expiresAt']);
      if (expiresAt == null || !expiresAt.isAfter(now)) {
        throw const CareServiceError(CareServiceErrorType.invitationExpired);
      }
      tx.update(invitationRef, {
        'status': InvitationStatus.claimed.rawValue,
        'claimedBy': user.uid,
        'claimedName': name,
        'claimedAt': FieldValue.serverTimestamp(),
      });
      tx.set(requestRef, {
        'userId': user.uid,
        'householdId': invitation.householdId,
        'invitationId': invitation.id,
        'name': name,
        'email': email,
        'status': JoinRequestStatus.pending.rawValue,
        // Server timestamp so the Security Rules' `createdAt == request.time`
        // claim check passes.
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    return HouseholdJoinRequest(
      userId: user.uid,
      householdId: invitation.householdId,
      invitationId: invitation.id,
      name: name,
      email: email,
      status: JoinRequestStatus.pending,
      createdAt: now,
    );
  }

  @override
  Future<HouseholdJoinRequest?> restorePendingJoinRequest() async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    final results = await _db
        .collectionGroup('joinRequests')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: JoinRequestStatus.pending.rawValue)
        .limit(1)
        .get();
    if (results.docs.isEmpty) return null;
    return _joinRequestFrom(results.docs.first);
  }

  @override
  Stream<HouseholdJoinRequest?> joinRequestStream(
    HouseholdJoinRequest request,
  ) {
    return _householdRef(request.householdId)
        .collection('joinRequests')
        .doc(request.userId)
        .snapshots()
        .map((snap) => snap.exists ? _joinRequestFrom(snap) : null);
  }

  @override
  Stream<List<HouseholdJoinRequest>> joinRequestsStream(String householdID) {
    return _householdRef(householdID)
        .collection('joinRequests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        // Filter client-side: reviewed requests stay in Firestore as an audit
        // trail, but only pending ones belong in the owner's approval list.
        // (A `where` clause here would need a composite index.)
        .map((snap) => snap.docs
            .map(_joinRequestFrom)
            .where((request) => request.status == JoinRequestStatus.pending)
            .toList());
  }

  @override
  Future<HouseholdInvitation?> getActiveInvitation(String householdID) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    final householdDoc = await _householdRef(householdID).get();
    final invitationID = householdDoc.data()?['activeInvitationID'] as String?;
    if (invitationID == null) return null;
    final doc = await _db.collection('invitations').doc(invitationID).get();
    if (!doc.exists) return null;
    final invitation = _invitationFrom(doc);
    if (invitation.status != InvitationStatus.active &&
        invitation.status != InvitationStatus.claimed) {
      return null;
    }
    return invitation;
  }

  @override
  Future<void> reviewJoinRequest({
    required String householdID,
    required HouseholdJoinRequest request,
    required bool approve,
  }) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    final householdRef = _householdRef(householdID);
    final requestRef = householdRef.collection('joinRequests').doc(request.userId);
    final memberRef = _memberRef(householdID, request.userId);
    final invitationRef = _db.collection('invitations').doc(request.invitationId);

    await _db.runTransaction((tx) async {
      final householdDoc = await tx.get(householdRef);
      if (!householdDoc.exists ||
          householdDoc.data()?['ownerID'] != user.uid) {
        throw const CareServiceError(CareServiceErrorType.notOwner);
      }
      final requestDoc = await tx.get(requestRef);
      if (!requestDoc.exists ||
          requestDoc.data()?['status'] != JoinRequestStatus.pending.rawValue) {
        throw const CareServiceError(CareServiceErrorType.invalidTransition);
      }
      final next =
          approve ? JoinRequestStatus.approved : JoinRequestStatus.rejected;
      final invitationNext = approve
          ? InvitationStatus.approved
          : InvitationStatus.rejected;
      tx.update(requestRef, {
        'status': next.rawValue,
        'reviewedBy': user.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      tx.update(invitationRef, {
        'status': invitationNext.rawValue,
        'reviewedBy': user.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      tx.update(householdRef, {
        'activeInvitationID': FieldValue.delete(),
      });
      if (approve) {
        tx.set(
          memberRef,
          _caregiverData(
            id: request.userId,
            displayName: request.name,
            role: 'caregiver',
          ),
        );
      }
    });
  }

  @override
  Future<void> removeMember(String householdID, String caregiverID) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    final householdRef = _householdRef(householdID);
    final memberRef = _memberRef(householdID, caregiverID);
    await _db.runTransaction((tx) async {
      final householdDoc = await tx.get(householdRef);
      if (!householdDoc.exists ||
          householdDoc.data()?['ownerID'] != user.uid) {
        throw const CareServiceError(CareServiceErrorType.notOwner);
      }
      if (caregiverID == user.uid) {
        throw const CareServiceError(CareServiceErrorType.notOwner);
      }
      tx.delete(memberRef);
    });
  }

  // -------------------------------------------------------------------------
  // Push notifications (FCM tokens live under member/devices)
  // -------------------------------------------------------------------------

  @override
  Future<void> savePushToken({
    required String householdID,
    required String caregiverID,
    required String token,
    required String platform,
  }) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    await _memberRef(householdID, caregiverID)
        .collection('devices')
        .doc(token)
        .set({
          'token': token,
          'platform': platform,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  @override
  Future<void> removePushToken({
    required String householdID,
    required String caregiverID,
    required String token,
  }) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    final ref = _memberRef(householdID, caregiverID)
        .collection('devices')
        .doc(token);
    final doc = await ref.get();
    if (doc.exists) await ref.delete();
  }

  @override
  Future<bool> notificationsEnabled({
    required String householdID,
    required String caregiverID,
  }) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    final doc = await _memberRef(householdID, caregiverID).get();
    return doc.data()?['notificationsEnabled'] as bool? ?? false;
  }

  @override
  Future<void> setNotificationsEnabled({
    required String householdID,
    required String caregiverID,
    required bool enabled,
  }) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    await _memberRef(householdID, caregiverID).update({
      'notificationsEnabled': enabled,
      'notificationUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // -------------------------------------------------------------------------
  // Health records: medication courses, doses, and medical history
  // -------------------------------------------------------------------------

  @override
  void observeMedicationPlans({
    required String householdID,
    required void Function(List<MedicationPlan>) onChange,
    required void Function(Object error) onError,
  }) {
    _medicationPlanSub?.cancel();
    _medicationPlanSub = _householdRef(householdID)
        .collection('medicationPlans')
        .snapshots()
        .listen(
          (snapshot) => onChange(
              snapshot.docs.map(_medicationPlanFrom).toList(growable: false)),
          onError: (Object e) => onError(_map(e)),
        );
  }

  @override
  void observeHealthRecords({
    required String householdID,
    required void Function(List<HealthRecord>) onChange,
    required void Function(Object error) onError,
  }) {
    _healthRecordSub?.cancel();
    _healthRecordSub = _householdRef(householdID)
        .collection('healthRecords')
        .snapshots()
        .listen(
          (snapshot) => onChange(
              snapshot.docs.map(_healthRecordFrom).toList(growable: false)),
          onError: (Object e) => onError(_map(e)),
        );
  }

  @override
  Future<void> saveMedicationPlan(
    MedicationPlan plan,
    String householdID,
  ) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    if (!plan.isValid) {
      throw const CareServiceError(CareServiceErrorType.invalidMedicationPlan);
    }
    final ref = _medicationPlanRef(householdID, plan.id);
    final existing = await ref.get();
    final data = _medicationPlanData(plan);
    if (existing.exists) {
      data['revision'] = _revision(existing.data()!) + 1;
      await ref.update(data);
    } else {
      data['createdAt'] = FieldValue.serverTimestamp();
      await ref.set(data);
    }
  }

  @override
  Future<void> deleteMedicationPlan(String planID, String householdID) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    await _medicationPlanRef(householdID, planID).delete();
  }

  @override
  Future<void> saveHealthRecord(
    HealthRecord record,
    String householdID,
  ) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    if (!record.isValid) {
      throw const CareServiceError(CareServiceErrorType.invalidHealthRecord);
    }
    if (record.attachments.length > HealthRecord.maxAttachments) {
      throw const CareServiceError(
          CareServiceErrorType.attachmentLimitReached);
    }
    final ref = _healthRecordRef(householdID, record.id);
    final existing = await ref.get();
    final data = _healthRecordData(record);
    if (existing.exists) {
      data['updatedAt'] = FieldValue.serverTimestamp();
      data['updatedByID'] = user.uid;
      data['revision'] = _revision(existing.data()!) + 1;
      await ref.update(data);
    } else {
      data['createdAt'] = FieldValue.serverTimestamp();
      await ref.set(data);
    }
  }

  @override
  Future<void> deleteHealthRecord(
    String recordID,
    String householdID,
  ) async {
    _ensureConfigured();
    await _ensureAuthenticated();
    await _healthRecordRef(householdID, recordID).delete();
  }

  @override
  void stopObserving() {
    _householdSub?.cancel();
    _taskSub?.cancel();
    _caregiverSub?.cancel();
    _routineSub?.cancel();
    _medicationPlanSub?.cancel();
    _healthRecordSub?.cancel();
    _householdSub = null;
    _taskSub = null;
    _caregiverSub = null;
    _routineSub = null;
    _medicationPlanSub = null;
    _healthRecordSub = null;
  }

  @override
  void leaveHousehold() {
    stopObserving();
    _clearSavedHouseholdID();
  }

  // -------------------------------------------------------------------------
  // Transactions
  // -------------------------------------------------------------------------

  Future<void> _mutateRequest(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> Function(Map<String, dynamic> data) build,
  ) async {
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) {
        throw const CareServiceError(CareServiceErrorType.taskNotFound);
      }
      final data = doc.data()!;
      _requireUnclaimed(data);
      tx.update(ref, build(data));
    });
  }

  // -------------------------------------------------------------------------
  // References and auth
  // -------------------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _householdRef(String id) =>
      _db.collection('households').doc(id);

  DocumentReference<Map<String, dynamic>> _memberRef(
    String householdID,
    String userID,
  ) =>
      _householdRef(householdID).collection('members').doc(userID);

  DocumentReference<Map<String, dynamic>> _routineRef(
    String householdID,
    String routineID,
  ) =>
      _householdRef(householdID).collection('routines').doc(routineID);

  DocumentReference<Map<String, dynamic>> _taskRef(
    String householdID,
    String taskID,
  ) =>
      _householdRef(householdID).collection('tasks').doc(taskID);

  DocumentReference<Map<String, dynamic>> _medicationPlanRef(
    String householdID,
    String planID,
  ) =>
      _householdRef(householdID).collection('medicationPlans').doc(planID);

  DocumentReference<Map<String, dynamic>> _healthRecordRef(
    String householdID,
    String recordID,
  ) =>
      _householdRef(householdID).collection('healthRecords').doc(recordID);

  void _ensureConfigured() {
    if (Firebase.apps.isEmpty) {
      throw const CareServiceError(CareServiceErrorType.firebaseNotConfigured);
    }
  }

  Future<User> _ensureAuthenticated() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) {
      throw const CareServiceError(CareServiceErrorType.authenticationFailed);
    }
    return current;
  }

  void _validate(Caregiver caregiver, String userID) {
    if (caregiver.id != userID) {
      throw const CareServiceError(CareServiceErrorType.notHouseholdMember);
    }
  }

  // -------------------------------------------------------------------------
  // Persistence helpers (shared_preferences replaces UserDefaults)
  // -------------------------------------------------------------------------

  Future<String?> _savedHouseholdID() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_householdIDKey);
  }

  Future<void> _saveHouseholdID(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_householdIDKey, id);
  }

  Future<void> _clearSavedHouseholdID() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_householdIDKey);
  }

  // -------------------------------------------------------------------------
  // Firestore (de)serialization — mirrors FirebaseModels.swift
  // -------------------------------------------------------------------------

  Household _householdFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final name = data?['name'] as String?;
    final inviteCode = data?['inviteCode'] as String?;
    if (name == null || inviteCode == null) {
      throw const CareServiceError(CareServiceErrorType.malformedData);
    }
    return Household(
      id: doc.id,
      name: name,
      inviteCode: inviteCode,
      pets: _petsFromData(data),
      timeZoneIdentifier: data?['timeZoneIdentifier'] as String? ?? '',
      ownerID: data?['ownerID'] as String?,
    );
  }

  List<Pet> _petsFromData(Map<String, dynamic>? data) {
    final raw = data?['pets'] as List?;
    if (raw != null) {
      return raw.map((e) => Pet.fromJson(e as Map<String, dynamic>)).toList();
    }
    final petName = data?['petName'] as String?;
    if (petName == null || petName.isEmpty) return const [];
    return [
      Pet(
        id: 'pet-legacy',
        name: petName,
        type: PetType.fromRaw(data?['petType'] as String? ?? 'cat'),
      ),
    ];
  }

  Caregiver _caregiverFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final displayName = doc.data()?['displayName'] as String?;
    if (displayName == null) {
      throw const CareServiceError(CareServiceErrorType.malformedData);
    }
    return Caregiver(id: doc.id, displayName: displayName);
  }

  CareRoutine _routineFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = data?['title'] as String?;
    final category = CareCategory.fromRaw(
      data?['category'] as String? ?? 'other',
      name: data?['categoryName'] as String?,
    );
    final priority = CarePriority.values
        .where((e) => e.rawValue == data?['priority'])
        .firstOrNull;
    final hour = _int(data?['hour']);
    final minute = _int(data?['minute']);
    final startDate = (data?['startDate'] as Timestamp?)?.toDate();
    final timeZoneIdentifier = data?['timeZoneIdentifier'] as String?;
    final createdByID = data?['createdByID'] as String?;
    final createdByName = data?['createdByName'] as String?;
    final isActive = data?['isActive'] as bool?;

    if (title == null ||
        hour == null ||
        minute == null ||
        startDate == null ||
        timeZoneIdentifier == null ||
        createdByID == null ||
        createdByName == null ||
        isActive == null) {
      throw const CareServiceError(CareServiceErrorType.malformedData);
    }

    final rawFrequency = data?['frequency'] as String?;
    return CareRoutine(
      id: doc.id,
      title: title,
      category: category,
      priority: priority ?? CarePriority.normal,
      frequency: rawFrequency == null
          ? CareRoutineFrequency.daily
          : CareRoutineFrequency.fromRaw(rawFrequency),
      weekdays: (data?['weekdays'] as List?)
              ?.whereType<num>()
              .map((e) => e.toInt())
              .toList() ??
          const [1, 2, 3, 4, 5, 6, 7],
      interval: _int(data?['interval']) ?? 1,
      petID: data?['petID'] as String?,
      petIds: (data?['petIds'] as List?)?.whereType<String>().toList() ??
          const [],
      hour: hour,
      minute: minute,
      startDate: startDate,
      timeZoneIdentifier: timeZoneIdentifier,
      createdByID: createdByID,
      createdByNameSnapshot: createdByName,
      isActive: isActive,
    );
  }

  CareTask _taskFrom(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    bool isServerConfirmed = true,
  }) {
    final data = doc.data();
    final title = data?['title'] as String?;
    final category = CareCategory.fromRaw(
      data?['category'] as String? ?? 'other',
      name: data?['categoryName'] as String?,
    );
    final dueTime = (data?['dueTime'] as Timestamp?)?.toDate();
    final status = _status(data?['status'] as String?);
    final createdBy = data?['createdBy'] as String?;

    if (title == null ||
        dueTime == null ||
        status == null ||
        createdBy == null) {
      throw const CareServiceError(CareServiceErrorType.malformedData);
    }

    AssignmentRequest? request;
    final requestID = data?['assignmentRequestID'] as String?;
    final requestedByID = data?['requestedByID'] as String?;
    final requestedByName = data?['requestedByName'] as String?;
    final requestedAt = (data?['assignmentRequestedAt'] as Timestamp?)?.toDate();
    if (requestID != null &&
        requestedByID != null &&
        requestedByName != null &&
        requestedAt != null) {
      final requestedToID = data?['requestedToID'] as String?;
      final rawMode = data?['assignmentMode'] as String?;
      request = AssignmentRequest(
        id: requestID,
        requestedByID: requestedByID,
        requestedByNameSnapshot: requestedByName,
        requestedToID: requestedToID,
        requestedToNameSnapshot: data?['requestedToName'] as String?,
        mode: rawMode == null
            ? (requestedToID == null ? AssignmentMode.open : AssignmentMode.direct)
            : AssignmentMode.fromRaw(rawMode),
        createdAt: requestedAt,
      );
    }

    return CareTask(
      id: doc.id,
      title: title,
      category: category,
      dueTime: dueTime,
      kind: CareTaskKind.fromRaw(data?['kind'] as String? ?? 'oneOff'),
      priority: CarePriority.fromRaw(data?['priority'] as String? ?? 'normal'),
      routineID: data?['routineID'] as String?,
      petID: data?['petID'] as String?,
      petIds: (data?['petIds'] as List?)?.whereType<String>().toList() ??
          const [],
      status: status,
      assignmentRequest: request,
      assigneeID: data?['assigneeID'] as String?,
      assigneeNameSnapshot: data?['assigneeName'] as String?,
      claimedAt: (data?['claimedAt'] as Timestamp?)?.toDate(),
      createdByID: data?['createdByID'] as String?,
      createdBy: createdBy,
      createdAt: (data?['createdAt'] as Timestamp?)?.toDate() ?? dueTime,
      completedByID: data?['completedByID'] as String?,
      completedBy: data?['completedBy'] as String?,
      completedAt: (data?['completedAt'] as Timestamp?)?.toDate(),
      revision: _int(data?['revision']) ?? 0,
      skipReason: data?['skipReason'] == null
          ? null
          : MedicationSkipReason.fromRaw(data!['skipReason'] as String),
      skipNote: data?['skipNote'] as String?,
      isServerConfirmed: isServerConfirmed,
    );
  }

  Map<String, dynamic> _householdData({
    required String id,
    required String name,
    required List<Pet> pets,
    required String timeZoneIdentifier,
    required String ownerID,
  }) {
    return {
      'id': id,
      'name': name,
      'pets': pets.map((e) => e.toJson()).toList(),
      'inviteCode': '',
      'timeZoneIdentifier': timeZoneIdentifier,
      'ownerID': ownerID,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _caregiverData({
    required String id,
    required String displayName,
    String role = 'caregiver',
  }) {
    return {
      'id': id,
      'displayName': displayName,
      'role': role,
      'joinedAt': FieldValue.serverTimestamp(),
    };
  }

  // ---- Health records -----------------------------------------------------

  MedicationPlan _medicationPlanFrom(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw const CareServiceError(CareServiceErrorType.malformedData);
    }
    return MedicationPlan(
      id: doc.id,
      petId: data['petId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      form: MedicationForm.fromRaw(data['form'] as String? ?? 'oral'),
      purpose: data['purpose'] as String?,
      sideEffects: data['sideEffects'] as String?,
      isActive: data['isActive'] as bool? ?? true,
      remainingDoses: _int(data['remainingDoses']),
      createdByID: data['createdByID'] as String? ?? '',
      createdByNameSnapshot: data['createdByName'] as String? ?? '',
      createdAt: _anyDate(data['createdAt']) ?? DateTime.now(),
      revision: _revision(data),
    );
  }

  Map<String, dynamic> _medicationPlanData(MedicationPlan plan) {
    return {
      'id': plan.id,
      'petId': plan.petId,
      'name': plan.name,
      'form': plan.form.rawValue,
      'purpose': plan.purpose,
      'sideEffects': plan.sideEffects,
      'isActive': plan.isActive,
      'remainingDoses': plan.remainingDoses,
      'createdByID': plan.createdByID,
      'createdByName': plan.createdByNameSnapshot,
      'revision': plan.revision,
    };
  }

  HealthRecord _healthRecordFrom(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw const CareServiceError(CareServiceErrorType.malformedData);
    }
    double? number(dynamic value) => value is num ? value.toDouble() : null;
    return HealthRecord(
      id: doc.id,
      petId: data['petId'] as String? ?? '',
      petNameSnapshot: data['petNameSnapshot'] as String? ?? '',
      type: HealthRecordType.fromRaw(data['type'] as String? ?? 'note'),
      occurredAt: _anyDate(data['occurredAt']) ?? DateTime.now(),
      title: data['title'] as String? ?? '',
      clinicName: data['clinicName'] as String?,
      vetName: data['vetName'] as String?,
      diagnosis: data['diagnosis'] as String?,
      treatment: data['treatment'] as String?,
      costMinor: _int(data['costMinor']),
      currency: data['currency'] as String?,
      productName: data['productName'] as String?,
      lotNumber: data['lotNumber'] as String?,
      nextDueAt: _anyDate(data['nextDueAt']),
      weightKg: number(data['weightKg']),
      temperatureC: number(data['temperatureC']),
      notes: data['notes'] as String?,
      attachments: (data['attachments'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => HealthAttachment.fromJson(e.cast<String, dynamic>()))
          .toList(),
      createdByID: data['createdByID'] as String? ?? '',
      createdByNameSnapshot: data['createdByName'] as String? ?? '',
      createdAt: _anyDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: _anyDate(data['updatedAt']),
      updatedByID: data['updatedByID'] as String?,
      updatedByNameSnapshot: data['updatedByName'] as String?,
      revision: _revision(data),
    );
  }

  Map<String, dynamic> _healthRecordData(HealthRecord record) {
    return {
      'id': record.id,
      'petId': record.petId,
      'petNameSnapshot': record.petNameSnapshot,
      'type': record.type.rawValue,
      'occurredAt': Timestamp.fromDate(record.occurredAt),
      'title': record.title,
      'clinicName': record.clinicName,
      'vetName': record.vetName,
      'diagnosis': record.diagnosis,
      'treatment': record.treatment,
      'costMinor': record.costMinor,
      'currency': record.currency,
      'productName': record.productName,
      'lotNumber': record.lotNumber,
      'nextDueAt': record.nextDueAt == null
          ? null
          : Timestamp.fromDate(record.nextDueAt!),
      'weightKg': record.weightKg,
      'temperatureC': record.temperatureC,
      'notes': record.notes,
      'attachments': record.attachments.map((e) => e.toJson()).toList(),
      'createdByID': record.createdByID,
      'createdByName': record.createdByNameSnapshot,
      'updatedByName': record.updatedByNameSnapshot,
      'revision': record.revision,
    };
  }

  Map<String, dynamic> _routineData(CareRoutine routine) {
    return {
      'id': routine.id,
      'title': routine.title,
      'category': routine.category.id,
      'categoryName': routine.category.name,
      'priority': routine.priority.rawValue,
      'frequency': routine.frequency.rawValue,
      'weekdays': routine.weekdays,
      'interval': routine.interval,
      'petID': routine.petID,
      'petIds': routine.petIds,
      'hour': routine.hour,
      'minute': routine.minute,
      'startDate': Timestamp.fromDate(routine.startDate),
      'timeZoneIdentifier': routine.timeZoneIdentifier,
      'createdByID': routine.createdByID,
      'createdByName': routine.createdByNameSnapshot,
      'isActive': routine.isActive,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _taskData(
    CareTask task, {
    required String createdByID,
    required bool useServerCreatedAt,
  }) {
    final request = task.assignmentRequest;
    return {
      'id': task.id,
      'title': task.title,
      'category': task.category.id,
      'categoryName': task.category.name,
      'dueTime': Timestamp.fromDate(task.dueTime),
      'kind': task.kind.rawValue,
      'priority': task.priority.rawValue,
      'routineID': task.routineID,
      'petID': task.petID,
      'petIds': task.petIds,
      'status': task.status.rawValue,
      'assignmentRequestID': request?.id,
      'assignmentMode': request?.mode.rawValue,
      'requestedByID': request?.requestedByID,
      'requestedByName': request?.requestedByNameSnapshot,
      'requestedToID': request?.requestedToID,
      'requestedToName': request?.requestedToNameSnapshot,
      'assignmentRequestedAt':
          request == null ? null : Timestamp.fromDate(request.createdAt),
      'assigneeID': task.assigneeID,
      'assigneeName': task.assigneeNameSnapshot,
      'claimedAt':
          task.claimedAt == null ? null : Timestamp.fromDate(task.claimedAt!),
      'createdByID': createdByID,
      'createdBy': task.createdBy,
      'createdAt': useServerCreatedAt
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(task.createdAt),
      'completedByID': task.completedByID,
      'completedBy': task.completedBy,
      'completedAt': task.completedAt == null
          ? null
          : Timestamp.fromDate(task.completedAt!),
      'skipReason': task.skipReason?.rawValue,
      'skipNote': task.skipNote,
      'revision': task.revision,
    };
  }

  Map<String, dynamic> _clearedRequest() {
    return {
      'assignmentRequestID': FieldValue.delete(),
      'assignmentMode': FieldValue.delete(),
      'requestedByID': FieldValue.delete(),
      'requestedByName': FieldValue.delete(),
      'requestedToID': FieldValue.delete(),
      'requestedToName': FieldValue.delete(),
      'assignmentRequestedAt': FieldValue.delete(),
    };
  }

  // -------------------------------------------------------------------------
  // Value helpers
  // -------------------------------------------------------------------------

  int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  int _revision(Map<String, dynamic> data) => _int(data['revision']) ?? 0;

  CareTaskStatus? _status(String? value) {
    switch (value) {
      case 'pending':
      case 'unclaimed':
        return CareTaskStatus.unclaimed;
      case 'claimed':
        return CareTaskStatus.claimed;
      case 'completed':
        return CareTaskStatus.completed;
      case 'skipped':
        return CareTaskStatus.skipped;
      default:
        return null;
    }
  }

  /// Reads a date written as a Firestore [Timestamp] or an epoch-millis int.
  DateTime? _anyDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  void _requireUnclaimed(Map<String, dynamic> data) {
    switch (_status(data['status'] as String?)) {
      case CareTaskStatus.unclaimed:
        return;
      case CareTaskStatus.claimed:
        throw CareServiceError(
          CareServiceErrorType.taskAlreadyClaimed,
          assigneeName: data['assigneeName'] as String?,
        );
      case CareTaskStatus.completed:
        throw const CareServiceError(CareServiceErrorType.taskAlreadyCompleted);
      case CareTaskStatus.skipped:
        throw const CareServiceError(CareServiceErrorType.invalidTransition);
      case null:
        throw const CareServiceError(CareServiceErrorType.invalidTransition);
    }
  }

  HouseholdInvitation _invitationFrom(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw const CareServiceError(CareServiceErrorType.malformedData);
    }
    String? str(dynamic value) => value as String?;
    return HouseholdInvitation(
      id: doc.id,
      householdId: data['householdId'] as String,
      householdName: data['householdName'] as String,
      petNames: (data['petNames'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      inviterName: data['inviterName'] as String,
      invitedBy: data['invitedBy'] as String,
      status: InvitationStatus.fromRaw(data['status'] as String? ?? 'active'),
      createdAt: _anyDate(data['createdAt']) ?? DateTime.now(),
      expiresAt: _anyDate(data['expiresAt']) ??
          DateTime.now().add(const Duration(hours: 24)),
      claimedBy: str(data['claimedBy']),
      claimedName: str(data['claimedName']),
      claimedAt: _anyDate(data['claimedAt']),
      reviewedBy: str(data['reviewedBy']),
      reviewedAt: _anyDate(data['reviewedAt']),
    );
  }

  HouseholdJoinRequest _joinRequestFrom(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw const CareServiceError(CareServiceErrorType.malformedData);
    }
    String? str(dynamic value) => value as String?;
    return HouseholdJoinRequest(
      userId: data['userId'] as String,
      householdId: data['householdId'] as String,
      invitationId: data['invitationId'] as String,
      name: data['name'] as String,
      email: str(data['email']),
      status: JoinRequestStatus.fromRaw(data['status'] as String? ?? 'pending'),
      createdAt: _anyDate(data['createdAt']) ?? DateTime.now(),
      reviewedBy: str(data['reviewedBy']),
      reviewedAt: _anyDate(data['reviewedAt']),
    );
  }

  void _requireMatchingRequest(Map<String, dynamic> data, String requestID) {
    if ((data['assignmentRequestID'] as String?) != requestID) {
      throw const CareServiceError(CareServiceErrorType.assignmentRequestChanged);
    }
  }

  CareServiceError _map(Object error) {
    if (error is CareServiceError) return error;
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return const CareServiceError(CareServiceErrorType.permissionDenied);
        case 'unavailable':
          return const CareServiceError(CareServiceErrorType.networkUnavailable);
        default:
          return const CareServiceError(CareServiceErrorType.backendUnavailable);
      }
    }
    return const CareServiceError(CareServiceErrorType.backendUnavailable);
  }
}
