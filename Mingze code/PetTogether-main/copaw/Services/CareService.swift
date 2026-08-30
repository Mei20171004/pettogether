import Foundation

@MainActor
protocol CareService: AnyObject {
    func restoreSession() async throws -> CareSession?

    func createHousehold(
        name: String,
        petName: String,
        caregiverName: String
    ) async throws -> CareSession

    func joinHousehold(
        inviteCode: String,
        caregiverName: String
    ) async throws -> CareSession

    func observeHousehold(
        householdID: String,
        onChange: @escaping (Household) -> Void,
        onError: @escaping (Error) -> Void
    )

    func observeTasks(
        householdID: String,
        onChange: @escaping ([CareTask]) -> Void,
        onError: @escaping (Error) -> Void
    )

    func observeCaregivers(
        householdID: String,
        onChange: @escaping ([Caregiver]) -> Void,
        onError: @escaping (Error) -> Void
    )

    func observeRoutines(
        householdID: String,
        onChange: @escaping ([CareRoutine]) -> Void,
        onError: @escaping (Error) -> Void
    )

    func addTask(_ task: CareTask, householdID: String) async throws
    func addRoutine(_ routine: CareRoutine, householdID: String) async throws

    func updateProfile(
        household: Household,
        caregiver: Caregiver
    ) async throws

    func leaveHousehold()

    func claimTask(
        _ task: CareTask,
        householdID: String,
        caregiver: Caregiver
    ) async throws

    func requestAssignment(
        for task: CareTask,
        householdID: String,
        requester: Caregiver,
        requestedCaregiver: Caregiver
    ) async throws

    func requestOpenAssignment(
        for task: CareTask,
        householdID: String,
        requester: Caregiver
    ) async throws

    func acceptAssignmentRequest(
        taskID: String,
        requestID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws

    func declineAssignmentRequest(
        taskID: String,
        requestID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws

    func cancelAssignmentRequest(
        taskID: String,
        requestID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws

    func completeTask(
        taskID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws

    func stopObserving()
}

enum CareServiceError: LocalizedError, Equatable {
    case firebaseNotConfigured
    case authenticationFailed
    case invalidInviteCode
    case inviteCodeUnavailable
    case networkUnavailable
    case permissionDenied
    case malformedData
    case backendUnavailable
    case householdMismatch
    case notHouseholdMember
    case caregiverNotFound
    case invalidProfile
    case cannotRequestSelf
    case taskNotFound
    case duplicateTask
    case duplicateRoutine
    case taskAlreadyClaimed(assigneeName: String?)
    case taskAlreadyCompleted
    case taskNotClaimed
    case notAssignee
    case assignmentRequestChanged
    case notRequestRecipient
    case notRequestOwner
    case invalidTransition

    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            "Firebase isn't configured yet. Add GoogleService-Info.plist and try again."
        case .authenticationFailed:
            "We couldn't start a secure care session. Please try again."
        case .invalidInviteCode:
            "We couldn't find that household. Check the invite code and try again."
        case .inviteCodeUnavailable:
            "We couldn't create an invite code. Please try again."
        case .networkUnavailable:
            "You're offline. Reconnect to the internet and try again."
        case .permissionDenied:
            "You don't have permission to access this household."
        case .malformedData:
            "Some household data couldn't be read. Please try again."
        case .backendUnavailable:
            "The care service is temporarily unavailable. Please try again."
        case .householdMismatch:
            "This household is no longer available. Refresh and try again."
        case .notHouseholdMember:
            "You are no longer a member of this household."
        case .caregiverNotFound:
            "That caregiver is no longer available."
        case .invalidProfile:
            "Check the profile details and try again."
        case .cannotRequestSelf:
            "Choose another caregiver for this request."
        case .taskNotFound:
            "This task is no longer available."
        case .duplicateTask:
            "This task already exists."
        case .duplicateRoutine:
            "This routine already exists."
        case let .taskAlreadyClaimed(assigneeName):
            if let assigneeName {
                "\(assigneeName) already claimed this task."
            } else {
                "Someone already claimed this task."
            }
        case .taskAlreadyCompleted:
            "Someone has already completed this task."
        case .taskNotClaimed:
            "Claim this task before marking it done."
        case .notAssignee:
            "Only the caregiver who claimed this task can mark it done."
        case .assignmentRequestChanged:
            "This assignment request has changed. Refresh and try again."
        case .notRequestRecipient:
            "This request was sent to another caregiver."
        case .notRequestOwner:
            "Only the caregiver who sent this request can cancel it."
        case .invalidTransition:
            "This task changed before your action finished. Refresh and try again."
        }
    }
}
