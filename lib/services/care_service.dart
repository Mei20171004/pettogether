import '../models/health.dart';
import '../models/models.dart';

enum CareServiceErrorType {
  firebaseNotConfigured,
  authenticationFailed,
  invalidInviteCode,
  inviteCodeUnavailable,
  networkUnavailable,
  permissionDenied,
  malformedData,
  backendUnavailable,
  householdMismatch,
  notHouseholdMember,
  caregiverNotFound,
  invalidProfile,
  cannotRequestSelf,
  taskNotFound,
  duplicateTask,
  duplicateRoutine,
  taskAlreadyClaimed,
  taskAlreadyCompleted,
  taskNotClaimed,
  notAssignee,
  assignmentRequestChanged,
  notRequestRecipient,
  notRequestOwner,
  invalidTransition,
  invitationNotFound,
  invitationExpired,
  invitationAlreadyClaimed,
  invitationRevoked,
  invitationUnavailable,
  alreadyMember,
  notOwner,
  joinRequestPending,
  medicationPlanNotFound,
  invalidMedicationPlan,
  healthRecordNotFound,
  invalidHealthRecord,
  attachmentTooLarge,
  attachmentLimitReached,
  attachmentUploadFailed,
}

/// Thrown by every [CareService] implementation. Carries a typed [type] and,
/// for `taskAlreadyClaimed`, the name of the caregiver who got there first.
class CareServiceError implements Exception {
  const CareServiceError(this.type, {this.assigneeName});

  final CareServiceErrorType type;
  final String? assigneeName;

  String get message {
    switch (type) {
      case CareServiceErrorType.firebaseNotConfigured:
        return "Firebase isn't configured yet. Add GoogleService-Info.plist and try again.";
      case CareServiceErrorType.authenticationFailed:
        return "We couldn't start a secure care session. Please try again.";
      case CareServiceErrorType.invalidInviteCode:
        return "We couldn't find that household. Check the invite code and try again.";
      case CareServiceErrorType.inviteCodeUnavailable:
        return "We couldn't create an invite code. Please try again.";
      case CareServiceErrorType.networkUnavailable:
        return "You're offline. Reconnect to the internet and try again.";
      case CareServiceErrorType.permissionDenied:
        return "You don't have permission to access this household.";
      case CareServiceErrorType.malformedData:
        return "Some household data couldn't be read. Please try again.";
      case CareServiceErrorType.backendUnavailable:
        return "The care service is temporarily unavailable. Please try again.";
      case CareServiceErrorType.householdMismatch:
        return "This household is no longer available. Refresh and try again.";
      case CareServiceErrorType.notHouseholdMember:
        return "You are no longer a member of this household.";
      case CareServiceErrorType.caregiverNotFound:
        return "That caregiver is no longer available.";
      case CareServiceErrorType.invalidProfile:
        return "Check the profile details and try again.";
      case CareServiceErrorType.cannotRequestSelf:
        return "Choose another caregiver for this request.";
      case CareServiceErrorType.taskNotFound:
        return "This task is no longer available.";
      case CareServiceErrorType.duplicateTask:
        return "This task already exists.";
      case CareServiceErrorType.duplicateRoutine:
        return "This routine already exists.";
      case CareServiceErrorType.taskAlreadyClaimed:
        return assigneeName != null
            ? '$assigneeName already claimed this task.'
            : 'Someone already claimed this task.';
      case CareServiceErrorType.taskAlreadyCompleted:
        return 'Someone has already completed this task.';
      case CareServiceErrorType.taskNotClaimed:
        return 'Claim this task before marking it done.';
      case CareServiceErrorType.notAssignee:
        return 'Only the caregiver who claimed this task can mark it done.';
      case CareServiceErrorType.assignmentRequestChanged:
        return 'This assignment request has changed. Refresh and try again.';
      case CareServiceErrorType.notRequestRecipient:
        return 'This request was sent to another caregiver.';
      case CareServiceErrorType.notRequestOwner:
        return 'Only the caregiver who sent this request can cancel it.';
      case CareServiceErrorType.invalidTransition:
        return 'This task changed before your action finished. Refresh and try again.';
      case CareServiceErrorType.invitationNotFound:
        return "We couldn't find that invitation. It may have expired or been revoked.";
      case CareServiceErrorType.invitationExpired:
        return 'This invitation expired. Ask the owner for a new one.';
      case CareServiceErrorType.invitationAlreadyClaimed:
        return 'This invitation has already been used by someone else.';
      case CareServiceErrorType.invitationRevoked:
        return 'This invitation was revoked by the household owner.';
      case CareServiceErrorType.invitationUnavailable:
        return 'That invitation is unavailable in local demo mode. Try PAW123.';
      case CareServiceErrorType.alreadyMember:
        return 'You are already a member of a household. Leave it before joining another.';
      case CareServiceErrorType.notOwner:
        return 'Only the household owner can do this.';
      case CareServiceErrorType.joinRequestPending:
        return 'Your request is still waiting for the owner’s approval.';
      case CareServiceErrorType.medicationPlanNotFound:
        return 'This medication course is no longer available.';
      case CareServiceErrorType.invalidMedicationPlan:
        return 'Check the medicine name, dose times and course dates, then try again.';
      case CareServiceErrorType.healthRecordNotFound:
        return 'This health record is no longer available.';
      case CareServiceErrorType.invalidHealthRecord:
        return 'Check the record details and try again.';
      case CareServiceErrorType.attachmentTooLarge:
        return "That photo is too large. Try one under 5 MB.";
      case CareServiceErrorType.attachmentLimitReached:
        return 'A record can hold up to 10 photos.';
      case CareServiceErrorType.attachmentUploadFailed:
        return "We couldn't upload that photo. Please try again.";
    }
  }

  @override
  String toString() => message;
}

/// The protocol-based service boundary from `CareService.swift`. The store
/// talks only to this interface, so the mock and Firebase implementations are
/// interchangeable.
abstract class CareService {
  Future<CareSession?> restoreSession();

  Future<CareSession> createHousehold({
    required String name,
    required List<Pet> pets,
    required String caregiverName,
  });

  void observeHousehold({
    required String householdID,
    required void Function(Household) onChange,
    required void Function(Object error) onError,
  });

  void observeTasks({
    required String householdID,
    required void Function(List<CareTask>) onChange,
    required void Function(Object error) onError,
  });

  void observeCaregivers({
    required String householdID,
    required void Function(List<Caregiver>) onChange,
    required void Function(Object error) onError,
  });

  void observeRoutines({
    required String householdID,
    required void Function(List<CareRoutine>) onChange,
    required void Function(Object error) onError,
  });

  Future<void> addTask(CareTask task, String householdID);
  Future<void> addRoutine(CareRoutine routine, String householdID);

  /// Replaces a routine in place, keeping its id so today's occurrence keeps
  /// pointing at the same document.
  Future<void> updateRoutine(CareRoutine routine, String householdID);

  Future<void> deleteRoutine(String routineID, String householdID);

  Future<void> updateProfile(Household household, Caregiver caregiver);

  Future<void> addPet(String householdID, Pet pet);

  Future<void> updatePet(String householdID, Pet pet);

  Future<void> removePet(String householdID, String petID);

  void leaveHousehold();

  Future<void> claimTask(
    CareTask task,
    String householdID,
    Caregiver caregiver,
  );

  Future<void> requestAssignment(
    CareTask task,
    String householdID,
    Caregiver requester,
    Caregiver requestedCaregiver,
  );

  Future<void> requestOpenAssignment(
    CareTask task,
    String householdID,
    Caregiver requester,
  );

  Future<void> acceptAssignmentRequest(
    String taskID,
    String requestID,
    String householdID,
    Caregiver caregiver,
  );

  Future<void> declineAssignmentRequest(
    String taskID,
    String requestID,
    String householdID,
    Caregiver caregiver,
  );

  Future<void> cancelAssignmentRequest(
    String taskID,
    String requestID,
    String householdID,
    Caregiver caregiver,
  );

  Future<void> completeTask(
    String taskID,
    String householdID,
    Caregiver caregiver,
  );

  /// Marks a single routine occurrence as skipped without touching the
  /// routine itself. Persists an override task document at the occurrence id.
  ///
  /// Medication doses pass a [reason]: "no walk today" needs no explanation,
  /// a missed dose does, and "refused it twice, vomited once" is a finding a
  /// vet can act on.
  Future<void> skipTaskOccurrence(
    CareTask task,
    String householdID,
    Caregiver caregiver, {
    MedicationSkipReason? reason,
    String? note,
  });

  /// Restores a previously skipped (or otherwise overridden) occurrence back
  /// to its routine-derived state (unclaimed).
  Future<void> restoreTaskOccurrence(
    CareTask task,
    String householdID,
    Caregiver caregiver,
  );

  // -------------------------------------------------------------------------
  // Invitations (one-time 24h link/QR + owner approval)
  // -------------------------------------------------------------------------

  /// Creates a fresh one-time invitation for the current user's household.
  Future<HouseholdInvitation> createInvitation({
    required String householdID,
    required String inviterName,
  });

  /// Loads an invitation by id (from a deep link or QR code).
  Future<HouseholdInvitation> loadInvitation(String invitationID);

  Future<void> revokeInvitation(String invitationID);

  /// Claims the invitation and files a pending join request for the current
  /// user. The owner must approve before any household data is shared.
  Future<HouseholdJoinRequest> requestToJoin({
    required HouseholdInvitation invitation,
    required String name,
    String? email,
  });

  /// Restores a still-pending join request after an app restart.
  Future<HouseholdJoinRequest?> restorePendingJoinRequest();

  Stream<HouseholdJoinRequest?> joinRequestStream(HouseholdJoinRequest request);

  Stream<List<HouseholdJoinRequest>> joinRequestsStream(String householdID);

  /// The household's current active/claimed invitation, if any.
  Future<HouseholdInvitation?> getActiveInvitation(String householdID);

  /// Approves (creates a member doc) or rejects the join request.
  Future<void> reviewJoinRequest({
    required String householdID,
    required HouseholdJoinRequest request,
    required bool approve,
  });

  /// Owner-only: removes a caregiver from the household.
  Future<void> removeMember(String householdID, String caregiverID);

  // -------------------------------------------------------------------------
  // Push notifications (FCM tokens live under member/devices)
  // -------------------------------------------------------------------------

  Future<void> savePushToken({
    required String householdID,
    required String caregiverID,
    required String token,
    required String platform,
  });

  Future<void> removePushToken({
    required String householdID,
    required String caregiverID,
    required String token,
  });

  Future<bool> notificationsEnabled({
    required String householdID,
    required String caregiverID,
  });

  Future<void> setNotificationsEnabled({
    required String householdID,
    required String caregiverID,
    required bool enabled,
  });

  // -------------------------------------------------------------------------
  // Health records: medication courses, doses, and medical history
  // -------------------------------------------------------------------------

  void observeMedicationPlans({
    required String householdID,
    required void Function(List<MedicationPlan>) onChange,
    required void Function(Object error) onError,
  });

  void observeHealthRecords({
    required String householdID,
    required void Function(List<HealthRecord>) onChange,
    required void Function(Object error) onError,
  });

  /// Creates or replaces the drug details of a course. The schedule lives on
  /// the course's routines, so it is written separately.
  Future<void> saveMedicationPlan(MedicationPlan plan, String householdID);

  Future<void> deleteMedicationPlan(String planID, String householdID);

  Future<void> saveHealthRecord(HealthRecord record, String householdID);

  Future<void> deleteHealthRecord(String recordID, String householdID);

  void stopObserving();
}
