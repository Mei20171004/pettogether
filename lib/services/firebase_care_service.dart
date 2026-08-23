import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../utils/extensions.dart';
import '../utils/id.dart';
import 'care_service.dart';

/// Firestore-backed [CareService], ported from `FirebaseCareService.swift` and
/// `FirebaseModels.swift`. Reads and writes the same document shape and the
/// same flattened assignment-request fields, so it interoperates with the
/// original app and its security rules.
class FirebaseCareService implements CareService {
  static const _householdIDKey = 'copaw.activeHouseholdID';
  static const _inviteCodeLength = 6;
  static const _inviteCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _inviteCodeAttempts = 5;

  StreamSubscription? _householdSub;
  StreamSubscription? _taskSub;
  StreamSubscription? _caregiverSub;
  StreamSubscription? _routineSub;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // -------------------------------------------------------------------------
  // Session
  // -------------------------------------------------------------------------

  @override
  Future<CareSession?> restoreSession() async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    final householdID = await _savedHouseholdID();
    if (householdID == null) return null;

    final householdDoc = await _householdRef(householdID).get();
    final memberDoc = await _memberRef(householdID, user.uid).get();
    if (!householdDoc.exists || !memberDoc.exists) {
      await _clearSavedHouseholdID();
      return null;
    }

    return CareSession(
      household: _householdFrom(householdDoc),
      caregiver: _caregiverFrom(memberDoc),
    );
  }

  @override
  Future<CareSession> createHousehold({
    required String name,
    required String petName,
    required PetType petType,
    required String caregiverName,
  }) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    final householdRef = _db.collection('households').doc();
    final timeZoneIdentifier = DateTime.now().timeZoneName;
    final pet = Pet(id: uuid(), name: petName, type: petType);

    for (var attempt = 0; attempt < _inviteCodeAttempts; attempt++) {
      final inviteCode = _makeInviteCode();
      final inviteRef = _db.collection('inviteCodes').doc(inviteCode);
      final memberRef = householdRef.collection('members').doc(user.uid);

      try {
        await _db.runTransaction((tx) async {
          final existingInvite = await tx.get(inviteRef);
          if (existingInvite.exists) throw _InviteCodeCollision();

          tx.set(
            householdRef,
            _householdData(
              id: householdRef.id,
              name: name,
              pets: [pet],
              inviteCode: inviteCode,
              timeZoneIdentifier: timeZoneIdentifier,
              ownerID: user.uid,
            ),
          );
          tx.set(
            memberRef,
            _caregiverData(
              id: user.uid,
              displayName: caregiverName,
              inviteCode: inviteCode,
            ),
          );
          tx.set(inviteRef, {
            'householdID': householdRef.id,
            'createdBy': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'active': true,
          });
        });

        await _saveHouseholdID(householdRef.id);
        return CareSession(
          household: Household(
            id: householdRef.id,
            name: name,
            inviteCode: inviteCode,
            pets: [pet],
            timeZoneIdentifier: timeZoneIdentifier,
          ),
          caregiver: Caregiver(id: user.uid, displayName: caregiverName),
        );
      } on _InviteCodeCollision {
        continue;
      } catch (error) {
        throw _map(error);
      }
    }

    throw const CareServiceError(CareServiceErrorType.inviteCodeUnavailable);
  }

  @override
  Future<CareSession> joinHousehold({
    required String inviteCode,
    required String caregiverName,
  }) async {
    _ensureConfigured();
    final user = await _ensureAuthenticated();
    final normalized = inviteCode.trim().toUpperCase();

    final validCode = normalized.length == _inviteCodeLength &&
        normalized.split('').every(_inviteCodeChars.contains);
    if (!validCode) {
      throw const CareServiceError(CareServiceErrorType.invalidInviteCode);
    }

    final inviteDoc = await _db.collection('inviteCodes').doc(normalized).get();
    final inviteData = inviteDoc.data();
    final householdID = inviteData?['householdID'] as String?;
    if (!inviteDoc.exists ||
        inviteData?['active'] == false ||
        householdID == null) {
      throw const CareServiceError(CareServiceErrorType.invalidInviteCode);
    }

    final memberRef = _memberRef(householdID, user.uid);
    final memberDoc = await memberRef.get();
    if (memberDoc.exists) {
      await memberRef.update({
        'displayName': caregiverName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await memberRef.set(
        _caregiverData(
          id: user.uid,
          displayName: caregiverName,
          inviteCode: normalized,
        ),
      );
    }

    final householdDoc = await _householdRef(householdID).get();
    if (!householdDoc.exists) {
      throw const CareServiceError(CareServiceErrorType.invalidInviteCode);
    }

    await _saveHouseholdID(householdID);
    return CareSession(
      household: _householdFrom(householdDoc),
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
        .snapshots()
        .listen(
          (snapshot) =>
              onChange(snapshot.docs.map(_taskFrom).toList(growable: false)),
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
  void stopObserving() {
    _householdSub?.cancel();
    _taskSub?.cancel();
    _caregiverSub?.cancel();
    _routineSub?.cancel();
    _householdSub = null;
    _taskSub = null;
    _caregiverSub = null;
    _routineSub = null;
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
      hour: hour,
      minute: minute,
      startDate: startDate,
      timeZoneIdentifier: timeZoneIdentifier,
      createdByID: createdByID,
      createdByNameSnapshot: createdByName,
      isActive: isActive,
    );
  }

  CareTask _taskFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
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
    );
  }

  Map<String, dynamic> _householdData({
    required String id,
    required String name,
    required List<Pet> pets,
    required String inviteCode,
    required String timeZoneIdentifier,
    required String ownerID,
  }) {
    return {
      'id': id,
      'name': name,
      'pets': pets.map((e) => e.toJson()).toList(),
      'inviteCode': inviteCode,
      'timeZoneIdentifier': timeZoneIdentifier,
      'ownerID': ownerID,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _caregiverData({
    required String id,
    required String displayName,
    required String inviteCode,
  }) {
    return {
      'id': id,
      'displayName': displayName,
      'inviteCode': inviteCode,
      'joinedAt': FieldValue.serverTimestamp(),
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
      default:
        return null;
    }
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
      case null:
        throw const CareServiceError(CareServiceErrorType.invalidTransition);
    }
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

  static String _makeInviteCode() {
    final random = Random.secure();
    return String.fromCharCodes(
      List.generate(
        _inviteCodeLength,
        (_) => _inviteCodeChars
            .codeUnitAt(random.nextInt(_inviteCodeChars.length)),
      ),
    );
  }
}

class _InviteCodeCollision implements Exception {}
