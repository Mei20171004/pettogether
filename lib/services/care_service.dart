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
}

/// Thrown by every [CareService] implementation. Carries a typed [type] and,
/// for `taskAlreadyClaimed`, the name of the caregiver who claimed it.
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
    required String petName,
    required PetType petType,
    required String caregiverName,
  });

  Future<CareSession> joinHousehold({
    required String inviteCode,
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

  void stopObserving();
}
