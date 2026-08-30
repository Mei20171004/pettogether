import Foundation

private struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

@MainActor
final class MockCareService: CareService {
    private static let demoPartner = Caregiver(
        id: "demo-caregiver-partner",
        displayName: "Alex"
    )

    private var household = Household(
        id: "demo-household",
        name: "Mochi Family",
        inviteCode: "PAW123",
        petName: "Mochi"
    )

    private var tasks: [CareTask] = []
    private var caregivers: [Caregiver] = []
    private var routines: [CareRoutine] = []
    private var caregiver: Caregiver?
    private var householdObserver: ((Household) -> Void)?
    private var householdErrorObserver: ((Error) -> Void)?
    private var taskObserver: (([CareTask]) -> Void)?
    private var taskErrorObserver: ((Error) -> Void)?
    private var caregiverObserver: (([Caregiver]) -> Void)?
    private var caregiverErrorObserver: ((Error) -> Void)?
    private var routineObserver: (([CareRoutine]) -> Void)?
    private var routineErrorObserver: ((Error) -> Void)?
    private let defaults = UserDefaults.standard

    private enum StorageKey {
        static let household = "copaw.mock.household"
        static let caregiver = "copaw.mock.caregiver"
        static let tasks = "copaw.mock.tasks"
        static let caregivers = "copaw.mock.caregivers"
        static let routines = "copaw.mock.routines"
    }

    init() {
        if let data = defaults.data(forKey: StorageKey.household),
           let savedHousehold = try? JSONDecoder().decode(Household.self, from: data) {
            household = savedHousehold
        }
        if let data = defaults.data(forKey: StorageKey.caregiver),
           let savedCaregiver = try? JSONDecoder().decode(Caregiver.self, from: data) {
            caregiver = savedCaregiver
        }
        if let data = defaults.data(forKey: StorageKey.caregivers),
           let savedCaregivers = try? JSONDecoder().decode([Caregiver].self, from: data) {
            caregivers = savedCaregivers
        }
        if let data = defaults.data(forKey: StorageKey.routines),
           let savedRoutines = try? JSONDecoder().decode([CareRoutine].self, from: data) {
            routines = savedRoutines
        }
        if let data = defaults.data(forKey: StorageKey.tasks) {
            if let savedTasks = try? JSONDecoder().decode([CareTask].self, from: data) {
                tasks = savedTasks
            } else if let lossyTasks = try? JSONDecoder().decode([FailableDecodable<CareTask>].self, from: data) {
                tasks = lossyTasks.compactMap(\.value)
            }
        }

        normalizePersistedData()
    }

    func restoreSession() async throws -> CareSession? {
        guard let caregiver else { return nil }
        ensureCaregiverRoster(for: caregiver)
        persist()
        return CareSession(household: household, caregiver: caregiver)
    }

    func createHousehold(
        name: String,
        petName: String,
        caregiverName: String
    ) async throws -> CareSession {
        household = Household(
            id: household.id,
            name: name,
            inviteCode: household.inviteCode,
            petName: petName,
            timeZoneIdentifier: TimeZone.current.identifier
        )
        let caregiver = Caregiver(id: UUID().uuidString, displayName: caregiverName)
        self.caregiver = caregiver
        caregivers = [caregiver, Self.demoPartner]
        routines = Self.seedRoutines(household: household, caregiver: caregiver)
        tasks = Self.seedTaskOverrides(
            household: household,
            caregiver: caregiver,
            partner: Self.demoPartner,
            routines: routines
        )
        persist()
        notifyAllObservers()
        return CareSession(household: household, caregiver: caregiver)
    }

    func joinHousehold(
        inviteCode: String,
        caregiverName: String
    ) async throws -> CareSession {
        guard inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            == household.inviteCode else {
            throw CareServiceError.invalidInviteCode
        }

        let caregiver = Caregiver(id: UUID().uuidString, displayName: caregiverName)
        self.caregiver = caregiver
        ensureCaregiverRoster(for: caregiver)
        if routines.isEmpty {
            routines = Self.seedRoutines(household: household, caregiver: caregiver)
        }
        if tasks.isEmpty {
            tasks = Self.seedTaskOverrides(
                household: household,
                caregiver: caregiver,
                partner: Self.demoPartner,
                routines: routines
            )
        }
        persist()
        notifyAllObservers()
        return CareSession(household: household, caregiver: caregiver)
    }

    func observeHousehold(
        householdID: String,
        onChange: @escaping (Household) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard householdID == household.id else {
            onError(CareServiceError.householdMismatch)
            return
        }
        householdObserver = onChange
        householdErrorObserver = onError
        onChange(household)
    }

    func observeTasks(
        householdID: String,
        onChange: @escaping ([CareTask]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard householdID == household.id else {
            onError(CareServiceError.householdMismatch)
            return
        }
        taskObserver = onChange
        taskErrorObserver = onError
        onChange(tasks)
    }

    func observeCaregivers(
        householdID: String,
        onChange: @escaping ([Caregiver]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard householdID == household.id else {
            onError(CareServiceError.householdMismatch)
            return
        }
        caregiverObserver = onChange
        caregiverErrorObserver = onError
        onChange(caregivers)
    }

    func observeRoutines(
        householdID: String,
        onChange: @escaping ([CareRoutine]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard householdID == household.id else {
            onError(CareServiceError.householdMismatch)
            return
        }
        routineObserver = onChange
        routineErrorObserver = onError
        onChange(routines)
    }

    func addTask(_ task: CareTask, householdID: String) async throws {
        try validateHousehold(householdID)
        guard !tasks.contains(where: { $0.id == task.id }) else {
            throw CareServiceError.duplicateTask
        }
        guard task.kind == .oneOff,
              task.status == .unclaimed,
              task.assigneeID == nil,
              task.completedAt == nil else {
            throw CareServiceError.invalidTransition
        }
        if let createdByID = task.createdByID {
            try validateMember(id: createdByID)
        }

        tasks.append(task)
        persist()
        notifyTaskObserver()
    }

    func addRoutine(_ routine: CareRoutine, householdID: String) async throws {
        try validateHousehold(householdID)
        try validateMember(id: routine.createdByID)
        guard !routines.contains(where: { $0.id == routine.id }) else {
            throw CareServiceError.duplicateRoutine
        }
        guard (0..<24).contains(routine.hour), (0..<60).contains(routine.minute) else {
            throw CareServiceError.invalidTransition
        }

        routines.append(routine)
        persist()
        notifyRoutineObserver()
    }

    func updateProfile(
        household: Household,
        caregiver: Caregiver
    ) async throws {
        try validateHousehold(household.id)
        _ = try validatedMember(caregiver)

        let householdName = household.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let petName = household.petName.trimmingCharacters(in: .whitespacesAndNewlines)
        let caregiverName = caregiver.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !householdName.isEmpty,
              householdName.count <= 60,
              !petName.isEmpty,
              petName.count <= 60,
              !caregiverName.isEmpty,
              caregiverName.count <= 50 else {
            throw CareServiceError.invalidProfile
        }

        self.household = Household(
            id: household.id,
            name: householdName,
            inviteCode: household.inviteCode,
            petName: petName,
            timeZoneIdentifier: household.timeZoneIdentifier
        )
        let updatedCaregiver = Caregiver(id: caregiver.id, displayName: caregiverName)
        self.caregiver = updatedCaregiver
        if let index = caregivers.firstIndex(where: { $0.id == caregiver.id }) {
            caregivers[index] = updatedCaregiver
        }
        persist()
        notifyAllObservers()
    }

    func claimTask(
        _ task: CareTask,
        householdID: String,
        caregiver: Caregiver
    ) async throws {
        try validateHousehold(householdID)
        let caregiver = try validatedMember(caregiver)
        let existing = try materializedTask(for: task)
        switch existing.task.status {
        case .unclaimed:
            break
        case .claimed:
            throw CareServiceError.taskAlreadyClaimed(
                assigneeName: existing.task.assigneeNameSnapshot
            )
        case .completed:
            throw CareServiceError.taskAlreadyCompleted
        }

        var updated = existing.task
        updated.status = .claimed
        updated.assignmentRequest = nil
        updated.assigneeID = caregiver.id
        updated.assigneeNameSnapshot = caregiver.displayName
        updated.claimedAt = Date()
        updated.revision += 1
        replaceOrAppend(updated, at: existing.index)
    }

    func requestAssignment(
        for task: CareTask,
        householdID: String,
        requester: Caregiver,
        requestedCaregiver: Caregiver
    ) async throws {
        try validateHousehold(householdID)
        let requester = try validatedMember(requester)
        let requestedCaregiver = try validatedMember(requestedCaregiver)
        guard requester.id != requestedCaregiver.id else {
            throw CareServiceError.cannotRequestSelf
        }

        let existing = try materializedTask(for: task)
        switch existing.task.status {
        case .unclaimed:
            break
        case .claimed:
            throw CareServiceError.taskAlreadyClaimed(
                assigneeName: existing.task.assigneeNameSnapshot
            )
        case .completed:
            throw CareServiceError.taskAlreadyCompleted
        }

        if let request = existing.task.assignmentRequest {
            if request.requestedByID == requester.id,
               request.requestedToID == requestedCaregiver.id {
                return
            }
            throw CareServiceError.assignmentRequestChanged
        }

        var updated = existing.task
        updated.assignmentRequest = AssignmentRequest(
            id: UUID().uuidString,
            requestedByID: requester.id,
            requestedByNameSnapshot: requester.displayName,
            requestedToID: requestedCaregiver.id,
            requestedToNameSnapshot: requestedCaregiver.displayName,
            createdAt: Date()
        )
        updated.revision += 1
        replaceOrAppend(updated, at: existing.index)
    }

    func requestOpenAssignment(
        for task: CareTask,
        householdID: String,
        requester: Caregiver
    ) async throws {
        try validateHousehold(householdID)
        let requester = try validatedMember(requester)
        let existing = try materializedTask(for: task)
        try validateUnclaimed(existing.task)

        if let request = existing.task.assignmentRequest {
            if request.requestedByID == requester.id, request.mode == .open {
                return
            }
            throw CareServiceError.assignmentRequestChanged
        }

        var updated = existing.task
        updated.assignmentRequest = AssignmentRequest(
            id: UUID().uuidString,
            requestedByID: requester.id,
            requestedByNameSnapshot: requester.displayName,
            requestedToID: nil,
            requestedToNameSnapshot: nil,
            mode: .open,
            createdAt: Date()
        )
        updated.revision += 1
        replaceOrAppend(updated, at: existing.index)
    }

    func acceptAssignmentRequest(
        taskID: String,
        requestID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws {
        try validateHousehold(householdID)
        let caregiver = try validatedMember(caregiver)
        let index = try taskIndex(for: taskID)
        let task = tasks[index]
        try validateUnclaimed(task)
        guard let request = task.assignmentRequest, request.id == requestID else {
            throw CareServiceError.assignmentRequestChanged
        }
        guard request.requestedToID == caregiver.id else {
            throw CareServiceError.notRequestRecipient
        }

        var updated = task
        updated.status = .claimed
        updated.assignmentRequest = nil
        updated.assigneeID = caregiver.id
        updated.assigneeNameSnapshot = caregiver.displayName
        updated.claimedAt = Date()
        updated.revision += 1
        replaceOrAppend(updated, at: index)
    }

    func declineAssignmentRequest(
        taskID: String,
        requestID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws {
        try validateHousehold(householdID)
        let caregiver = try validatedMember(caregiver)
        let index = try taskIndex(for: taskID)
        let task = tasks[index]
        try validateUnclaimed(task)
        guard let request = task.assignmentRequest, request.id == requestID else {
            throw CareServiceError.assignmentRequestChanged
        }
        guard request.requestedToID == caregiver.id else {
            throw CareServiceError.notRequestRecipient
        }

        var updated = task
        updated.assignmentRequest = nil
        updated.revision += 1
        replaceOrAppend(updated, at: index)
    }

    func cancelAssignmentRequest(
        taskID: String,
        requestID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws {
        try validateHousehold(householdID)
        let caregiver = try validatedMember(caregiver)
        let index = try taskIndex(for: taskID)
        let task = tasks[index]
        try validateUnclaimed(task)
        guard let request = task.assignmentRequest, request.id == requestID else {
            throw CareServiceError.assignmentRequestChanged
        }
        guard request.requestedByID == caregiver.id else {
            throw CareServiceError.notRequestOwner
        }

        var updated = task
        updated.assignmentRequest = nil
        updated.revision += 1
        replaceOrAppend(updated, at: index)
    }

    func completeTask(
        taskID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws {
        try validateHousehold(householdID)
        let caregiver = try validatedMember(caregiver)
        let index = try taskIndex(for: taskID)
        let task = tasks[index]
        switch task.status {
        case .unclaimed:
            throw CareServiceError.taskNotClaimed
        case .claimed:
            guard task.assigneeID == caregiver.id else {
                throw CareServiceError.notAssignee
            }
        case .completed:
            throw CareServiceError.taskAlreadyCompleted
        }

        var updated = task
        updated.status = .completed
        updated.assignmentRequest = nil
        updated.completedByID = caregiver.id
        updated.completedBy = caregiver.displayName
        updated.completedAt = Date()
        updated.revision += 1
        replaceOrAppend(updated, at: index)
    }

    func stopObserving() {
        householdObserver = nil
        householdErrorObserver = nil
        taskObserver = nil
        taskErrorObserver = nil
        caregiverObserver = nil
        caregiverErrorObserver = nil
        routineObserver = nil
        routineErrorObserver = nil
    }

    func leaveHousehold() {
        stopObserving()
        caregiver = nil
        defaults.removeObject(forKey: StorageKey.caregiver)
    }

    private func validateHousehold(_ householdID: String) throws {
        guard householdID == household.id else {
            throw CareServiceError.householdMismatch
        }
    }

    private func validatedMember(_ caregiver: Caregiver) throws -> Caregiver {
        guard let savedCaregiver = caregivers.first(where: { $0.id == caregiver.id }) else {
            throw CareServiceError.notHouseholdMember
        }
        return savedCaregiver
    }

    private func validateMember(id: String) throws {
        guard caregivers.contains(where: { $0.id == id }) else {
            throw CareServiceError.notHouseholdMember
        }
    }

    private func validateUnclaimed(_ task: CareTask) throws {
        switch task.status {
        case .unclaimed:
            return
        case .claimed:
            throw CareServiceError.taskAlreadyClaimed(assigneeName: task.assigneeNameSnapshot)
        case .completed:
            throw CareServiceError.taskAlreadyCompleted
        }
    }

    private func taskIndex(for taskID: String) throws -> Int {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw CareServiceError.taskNotFound
        }
        return index
    }

    private func materializedTask(for task: CareTask) throws -> (task: CareTask, index: Int?) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            return (tasks[index], index)
        }
        guard task.kind == .routine,
              let routineID = task.routineID,
              let routine = routines.first(where: { $0.id == routineID && $0.isActive }),
              task.id == Self.occurrenceID(for: routine, on: task.dueTime, household: household) else {
            throw CareServiceError.taskNotFound
        }
        return (task, nil)
    }

    private func replaceOrAppend(_ task: CareTask, at index: Int?) {
        if let index {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        persist()
        notifyTaskObserver()
    }

    private func notifyTaskObserver() {
        taskObserver?(tasks)
    }

    private func notifyRoutineObserver() {
        routineObserver?(routines)
    }

    private func notifyAllObservers() {
        householdObserver?(household)
        taskObserver?(tasks)
        caregiverObserver?(caregivers)
        routineObserver?(routines)
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(household), forKey: StorageKey.household)
        defaults.set(try? JSONEncoder().encode(caregiver), forKey: StorageKey.caregiver)
        defaults.set(try? JSONEncoder().encode(tasks), forKey: StorageKey.tasks)
        defaults.set(try? JSONEncoder().encode(caregivers), forKey: StorageKey.caregivers)
        defaults.set(try? JSONEncoder().encode(routines), forKey: StorageKey.routines)
    }

    private func normalizePersistedData() {
        guard let caregiver else {
            caregivers = [Self.demoPartner]
            return
        }

        ensureCaregiverRoster(for: caregiver)
        let demoRoutines = Self.seedRoutines(household: household, caregiver: caregiver)
        let routinesByLegacyID = Dictionary(
            uniqueKeysWithValues: demoRoutines.map { (Self.legacyTaskID(for: $0.id), $0) }
        )
        var normalizedTasks: [CareTask] = []

        for task in tasks {
            guard task.kind == .oneOff,
                  task.routineID == nil,
                  let routine = routinesByLegacyID[task.id] else {
                normalizedTasks.append(Self.backfillCaregiverIDs(in: task, caregivers: caregivers))
                continue
            }

            if !routines.contains(where: { $0.id == routine.id }) {
                routines.append(routine)
            }
            let migrated = Self.migrateLegacyDemoTask(
                task,
                to: routine,
                household: household,
                caregivers: caregivers
            )
            if !normalizedTasks.contains(where: { $0.id == migrated.id }) {
                normalizedTasks.append(migrated)
            }
        }

        tasks = normalizedTasks
        persist()
    }

    private func ensureCaregiverRoster(for currentCaregiver: Caregiver) {
        caregivers.removeAll { $0.id == currentCaregiver.id || $0.id == Self.demoPartner.id }
        caregivers.insert(currentCaregiver, at: 0)
        caregivers.append(Self.demoPartner)
    }

    private static func seedRoutines(
        household: Household,
        caregiver: Caregiver
    ) -> [CareRoutine] {
        let startDate = householdCalendar(household).startOfDay(for: Date())
        return [
            CareRoutine(
                id: "demo-routine-brush-coat",
                title: "Brush coat",
                category: .grooming,
                hour: 7,
                minute: 30,
                startDate: startDate,
                timeZoneIdentifier: household.timeZoneIdentifier,
                createdByID: caregiver.id,
                createdByNameSnapshot: caregiver.displayName
            ),
            CareRoutine(
                id: "demo-routine-morning-meal",
                title: "Morning meal",
                category: .feeding,
                hour: 8,
                minute: 0,
                startDate: startDate,
                timeZoneIdentifier: household.timeZoneIdentifier,
                createdByID: caregiver.id,
                createdByNameSnapshot: caregiver.displayName
            ),
            CareRoutine(
                id: "demo-routine-allergy-medicine",
                title: "Give allergy medicine",
                category: .medication,
                hour: 10,
                minute: 30,
                startDate: startDate,
                timeZoneIdentifier: household.timeZoneIdentifier,
                createdByID: caregiver.id,
                createdByNameSnapshot: caregiver.displayName
            ),
            CareRoutine(
                id: "demo-routine-evening-walk",
                title: "Evening walk",
                category: .walking,
                hour: 18,
                minute: 30,
                startDate: startDate,
                timeZoneIdentifier: household.timeZoneIdentifier,
                createdByID: caregiver.id,
                createdByNameSnapshot: caregiver.displayName
            )
        ]
    }

    private static func seedTaskOverrides(
        household: Household,
        caregiver: Caregiver,
        partner: Caregiver,
        routines: [CareRoutine]
    ) -> [CareTask] {
        guard let routine = routines.first(where: { $0.id == "demo-routine-brush-coat" }),
              let dueTime = dueTime(for: routine, on: Date(), household: household) else {
            return []
        }
        return [
            CareTask(
                id: occurrenceID(for: routine, on: dueTime, household: household),
                title: routine.title,
                category: routine.category,
                dueTime: dueTime,
                kind: .routine,
                priority: routine.priority,
                routineID: routine.id,
                status: .completed,
                assigneeID: partner.id,
                assigneeNameSnapshot: partner.displayName,
                claimedAt: dueTime,
                createdByID: caregiver.id,
                createdBy: caregiver.displayName,
                createdAt: routine.startDate,
                completedByID: partner.id,
                completedBy: partner.displayName,
                completedAt: dueTime.addingTimeInterval(15 * 60),
                revision: 1
            )
        ]
    }

    private static func backfillCaregiverIDs(
        in task: CareTask,
        caregivers: [Caregiver]
    ) -> CareTask {
        var task = task
        if task.createdByID == nil {
            task.createdByID = uniqueCaregiverID(named: task.createdBy, in: caregivers)
        }
        if task.completedByID == nil, let completedBy = task.completedBy {
            task.completedByID = uniqueCaregiverID(named: completedBy, in: caregivers)
        }
        return task
    }

    private static func migrateLegacyDemoTask(
        _ task: CareTask,
        to routine: CareRoutine,
        household: Household,
        caregivers: [Caregiver]
    ) -> CareTask {
        let task = backfillCaregiverIDs(in: task, caregivers: caregivers)
        return CareTask(
            id: occurrenceID(for: routine, on: task.dueTime, household: household),
            title: task.title,
            category: task.category,
            dueTime: task.dueTime,
            kind: .routine,
            priority: task.priority,
            routineID: routine.id,
            status: task.status,
            assignmentRequest: task.assignmentRequest,
            assigneeID: task.assigneeID,
            assigneeNameSnapshot: task.assigneeNameSnapshot,
            claimedAt: task.claimedAt,
            createdByID: task.createdByID,
            createdBy: task.createdBy,
            createdAt: task.createdAt,
            completedByID: task.completedByID,
            completedBy: task.completedBy,
            completedAt: task.completedAt,
            revision: task.revision
        )
    }

    private static func uniqueCaregiverID(
        named name: String,
        in caregivers: [Caregiver]
    ) -> String? {
        let matches = caregivers.filter { $0.displayName == name }
        return matches.count == 1 ? matches[0].id : nil
    }

    private static func legacyTaskID(for routineID: String) -> String {
        routineID.replacingOccurrences(of: "demo-routine-", with: "demo-")
    }

    private static func householdCalendar(_ household: Household) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: household.timeZoneIdentifier) ?? .current
        return calendar
    }

    private static func occurrenceID(
        for routine: CareRoutine,
        on date: Date,
        household: Household
    ) -> String {
        let components = householdCalendar(household).dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%@_%04d-%02d-%02d",
            routine.id,
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func dueTime(
        for routine: CareRoutine,
        on day: Date,
        household: Household
    ) -> Date? {
        let calendar = householdCalendar(household)
        guard routine.frequency == .daily
                || routine.weekdays.contains(calendar.component(.weekday, from: day)) else {
            return nil
        }
        let startOfDay = calendar.startOfDay(for: day)
        return calendar.nextDate(
            after: startOfDay.addingTimeInterval(-1),
            matching: DateComponents(hour: routine.hour, minute: routine.minute),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}
