import Foundation

@MainActor
final class CareStore: ObservableObject {
    @Published private(set) var household: Household?
    @Published private(set) var currentCaregiver: Caregiver?
    @Published private(set) var tasks: [CareTask] = []
    @Published private(set) var caregivers: [Caregiver] = []
    @Published private(set) var routines: [CareRoutine] = []
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRestoringSession = true
    @Published private(set) var isSavingTask = false
    @Published private(set) var isSavingProfile = false
    @Published private(set) var mutatingTaskIDs: Set<String> = []
    @Published private(set) var petPhotoData: Data?

    private let service: CareService
    private var sessionRequestGeneration = 0
    private var didAttemptSessionRestore = false

    init(service: CareService? = nil) {
        self.service = service ?? MockCareService()
    }

    var partnerCaregiver: Caregiver? {
        guard let currentCaregiver else { return nil }
        return caregivers.first { $0.id != currentCaregiver.id }
    }

    var todayTasks: [CareTask] {
        tasks(on: Date())
    }

    var unclaimedTasks: [CareTask] {
        unclaimedTasks(on: Date())
    }

    var claimedTasks: [CareTask] {
        claimedTasks(on: Date())
    }

    var completedTasks: [CareTask] {
        completedTasks(on: Date())
    }

    @available(*, deprecated, message: "Use unclaimedTasks or unclaimedTasks(on:)")
    var pendingTasks: [CareTask] {
        unclaimedTasks
    }

    @available(*, deprecated, message: "Use mutatingTaskIDs")
    var completingTaskIDs: Set<String> {
        mutatingTaskIDs
    }

    func tasks(on date: Date) -> [CareTask] {
        guard let household else { return [] }
        let calendar = calendar(for: household)
        let selectedDay = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        let persistedForDay = tasks.filter {
            $0.dueTime >= selectedDay && $0.dueTime < nextDay
        }
        let overridesByID = Dictionary(
            persistedForDay.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        var result: [CareTask] = []
        var includedIDs: Set<String> = []

        for routine in routines where routine.isActive {
            let routineStartDay = calendar.startOfDay(for: routine.startDate)
            guard selectedDay >= routineStartDay,
                  routine.frequency == .daily
                    || routine.weekdays.contains(calendar.component(.weekday, from: selectedDay)),
                  let dueTime = dueTime(for: routine, on: selectedDay, calendar: calendar),
                  dueTime < nextDay else {
                continue
            }

            let taskID = occurrenceID(for: routine, on: selectedDay, calendar: calendar)
            let occurrence = overridesByID[taskID] ?? CareTask(
                id: taskID,
                title: routine.title,
                category: routine.category,
                dueTime: dueTime,
                kind: .routine,
                priority: routine.priority,
                routineID: routine.id,
                status: .unclaimed,
                createdByID: routine.createdByID,
                createdBy: routine.createdByNameSnapshot,
                createdAt: routine.startDate
            )
            result.append(occurrence)
            includedIDs.insert(taskID)
        }

        for task in persistedForDay where !includedIDs.contains(task.id) {
            result.append(task)
            includedIDs.insert(task.id)
        }

        return result.sorted {
            if $0.dueTime == $1.dueTime {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.dueTime < $1.dueTime
        }
    }

    func unclaimedTasks(on date: Date) -> [CareTask] {
        tasks(on: date).filter { $0.status == .unclaimed }
    }

    func claimedTasks(on date: Date) -> [CareTask] {
        tasks(on: date).filter { $0.status == .claimed }
    }

    func completedTasks(on date: Date) -> [CareTask] {
        tasks(on: date)
            .filter { $0.status == .completed }
            .sorted {
                ($0.completedAt ?? $0.dueTime) > ($1.completedAt ?? $1.dueTime)
            }
    }

    func restoreSession() async {
        guard !didAttemptSessionRestore else { return }
        didAttemptSessionRestore = true
        await restoreSessionIfAvailable()
    }

    func createHousehold(name: String, petName: String, caregiverName: String) {
        guard !isLoading else { return }
        sessionRequestGeneration += 1
        let generation = sessionRequestGeneration
        isLoading = true
        Task {
            await performSessionRequest(generation: generation) {
                try await service.createHousehold(
                    name: name,
                    petName: petName,
                    caregiverName: caregiverName
                )
            }
        }
    }

    func joinHousehold(inviteCode: String, caregiverName: String) {
        guard !isLoading else { return }
        sessionRequestGeneration += 1
        let generation = sessionRequestGeneration
        isLoading = true
        Task {
            await performSessionRequest(generation: generation) {
                try await service.joinHousehold(
                    inviteCode: inviteCode,
                    caregiverName: caregiverName
                )
            }
        }
    }

    func addTask(
        title: String,
        category: CareCategory,
        kind: CareTaskKind,
        priority: CarePriority,
        date: Date,
        frequency: CareRoutineFrequency = .daily,
        weekdays: [Int] = Array(1...7)
    ) async -> Bool {
        guard let household, let currentCaregiver, !isSavingTask else { return false }
        let generation = sessionRequestGeneration
        isSavingTask = true
        errorMessage = nil
        defer { isSavingTask = false }

        do {
            switch kind {
            case .oneOff:
                let task = CareTask(
                    id: UUID().uuidString,
                    title: title,
                    category: category,
                    dueTime: date,
                    kind: .oneOff,
                    priority: priority,
                    status: .unclaimed,
                    createdByID: currentCaregiver.id,
                    createdBy: currentCaregiver.displayName,
                    createdAt: Date()
                )
                try await service.addTask(task, householdID: household.id)
            case .routine:
                let calendar = calendar(for: household)
                let time = calendar.dateComponents([.hour, .minute], from: date)
                let routine = CareRoutine(
                    id: UUID().uuidString,
                    title: title,
                    category: category,
                    priority: priority,
                    frequency: frequency,
                    weekdays: weekdays,
                    hour: time.hour ?? 0,
                    minute: time.minute ?? 0,
                    startDate: calendar.startOfDay(for: date),
                    timeZoneIdentifier: household.timeZoneIdentifier,
                    createdByID: currentCaregiver.id,
                    createdByNameSnapshot: currentCaregiver.displayName
                )
                try await service.addRoutine(routine, householdID: household.id)
            }
            return generation == sessionRequestGeneration
        } catch {
            guard generation == sessionRequestGeneration else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addTask(title: String, category: CareCategory, dueTime: Date) async -> Bool {
        await addTask(
            title: title,
            category: category,
            kind: .oneOff,
            priority: .normal,
            date: dueTime
        )
    }

    func updateProfile(
        caregiverName: String,
        householdName: String,
        petName: String
    ) async -> Bool {
        guard let existingHousehold = household,
              let existingCaregiver = currentCaregiver,
              !isSavingProfile else {
            return false
        }

        let caregiverName = caregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let householdName = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        let petName = petName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !caregiverName.isEmpty,
              caregiverName.count <= 50,
              !householdName.isEmpty,
              householdName.count <= 60,
              !petName.isEmpty,
              petName.count <= 60 else {
            errorMessage = CareServiceError.invalidProfile.localizedDescription
            return false
        }

        var updatedHousehold = existingHousehold
        updatedHousehold.name = householdName
        updatedHousehold.petName = petName
        var updatedCaregiver = existingCaregiver
        updatedCaregiver.displayName = caregiverName

        let generation = sessionRequestGeneration
        isSavingProfile = true
        errorMessage = nil
        defer { isSavingProfile = false }

        do {
            try await service.updateProfile(
                household: updatedHousehold,
                caregiver: updatedCaregiver
            )
            guard generation == sessionRequestGeneration else { return false }
            household = updatedHousehold
            currentCaregiver = updatedCaregiver
            if let index = caregivers.firstIndex(where: { $0.id == updatedCaregiver.id }) {
                caregivers[index] = updatedCaregiver
            }
            return true
        } catch {
            guard generation == sessionRequestGeneration else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func savePetPhoto(_ data: Data?) throws {
        guard let household else { return }
        let photoURL = try petPhotoURL(for: household.id)

        if let data {
            try FileManager.default.createDirectory(
                at: photoURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: photoURL, options: [.atomic, .completeFileProtection])
        } else if FileManager.default.fileExists(atPath: photoURL.path) {
            try FileManager.default.removeItem(at: photoURL)
        }

        petPhotoData = data
    }

    func claim(_ task: CareTask) async -> Bool {
        guard let household, let currentCaregiver else { return false }
        return await performTaskMutation(taskID: task.id) {
            try await service.claimTask(
                task,
                householdID: household.id,
                caregiver: currentCaregiver
            )
        }
    }

    func request(_ task: CareTask, from requestedCaregiver: Caregiver) async -> Bool {
        guard let household, let currentCaregiver else { return false }
        return await performTaskMutation(taskID: task.id) {
            try await service.requestAssignment(
                for: task,
                householdID: household.id,
                requester: currentCaregiver,
                requestedCaregiver: requestedCaregiver
            )
        }
    }

    func requestPartner(for task: CareTask) async -> Bool {
        guard let partnerCaregiver else {
            errorMessage = CareServiceError.caregiverNotFound.localizedDescription
            return false
        }
        return await request(task, from: partnerCaregiver)
    }

    func requestAnyone(for task: CareTask) async -> Bool {
        guard let household, let currentCaregiver else { return false }
        return await performTaskMutation(taskID: task.id) {
            try await service.requestOpenAssignment(
                for: task,
                householdID: household.id,
                requester: currentCaregiver
            )
        }
    }

    func acceptRequest(for task: CareTask) async -> Bool {
        guard let household,
              let currentCaregiver,
              let request = task.assignmentRequest else {
            return false
        }
        return await performTaskMutation(taskID: task.id) {
            try await service.acceptAssignmentRequest(
                taskID: task.id,
                requestID: request.id,
                householdID: household.id,
                caregiver: currentCaregiver
            )
        }
    }

    func declineRequest(for task: CareTask) async -> Bool {
        guard let household,
              let currentCaregiver,
              let request = task.assignmentRequest else {
            return false
        }
        return await performTaskMutation(taskID: task.id) {
            try await service.declineAssignmentRequest(
                taskID: task.id,
                requestID: request.id,
                householdID: household.id,
                caregiver: currentCaregiver
            )
        }
    }

    func cancelRequest(for task: CareTask) async -> Bool {
        guard let household,
              let currentCaregiver,
              let request = task.assignmentRequest else {
            return false
        }
        return await performTaskMutation(taskID: task.id) {
            try await service.cancelAssignmentRequest(
                taskID: task.id,
                requestID: request.id,
                householdID: household.id,
                caregiver: currentCaregiver
            )
        }
    }

    func complete(_ task: CareTask) async -> Bool {
        guard let household, let currentCaregiver else { return false }
        return await performTaskMutation(taskID: task.id) {
            try await service.completeTask(
                taskID: task.id,
                householdID: household.id,
                caregiver: currentCaregiver
            )
        }
    }

    func leaveHousehold() {
        sessionRequestGeneration += 1
        service.leaveHousehold()
        household = nil
        currentCaregiver = nil
        tasks = []
        caregivers = []
        routines = []
        mutatingTaskIDs = []
        petPhotoData = nil
        isLoading = false
        isSavingTask = false
        isSavingProfile = false
        errorMessage = nil
    }

    private func performTaskMutation(
        taskID: String,
        _ mutation: () async throws -> Void
    ) async -> Bool {
        guard !mutatingTaskIDs.contains(taskID) else { return false }
        let generation = sessionRequestGeneration
        mutatingTaskIDs.insert(taskID)
        errorMessage = nil
        defer { mutatingTaskIDs.remove(taskID) }

        do {
            try await mutation()
            return generation == sessionRequestGeneration
        } catch {
            guard generation == sessionRequestGeneration else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func performSessionRequest(
        generation: Int,
        _ request: () async throws -> CareSession
    ) async {
        errorMessage = nil
        defer {
            if generation == sessionRequestGeneration {
                isLoading = false
            }
        }

        do {
            let session = try await request()
            guard generation == sessionRequestGeneration else { return }
            household = session.household
            currentCaregiver = session.caregiver
            loadPetPhoto(for: session.household.id)
            observeDomain(for: session)
        } catch {
            guard generation == sessionRequestGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func restoreSessionIfAvailable() async {
        let generation = sessionRequestGeneration
        defer { isRestoringSession = false }

        do {
            guard let session = try await service.restoreSession() else { return }
            guard generation == sessionRequestGeneration else { return }
            household = session.household
            currentCaregiver = session.caregiver
            loadPetPhoto(for: session.household.id)
            observeDomain(for: session)
        } catch {
            guard generation == sessionRequestGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func observeDomain(for session: CareSession) {
        service.stopObserving()
        service.observeHousehold(
            householdID: session.household.id,
            onChange: { [weak self] household in
                self?.household = household
            },
            onError: { [weak self] error in
                self?.errorMessage = error.localizedDescription
            }
        )
        service.observeTasks(
            householdID: session.household.id,
            onChange: { [weak self] tasks in
                self?.tasks = tasks
            },
            onError: { [weak self] error in
                self?.errorMessage = error.localizedDescription
            }
        )
        service.observeCaregivers(
            householdID: session.household.id,
            onChange: { [weak self] caregivers in
                guard let self else { return }
                self.caregivers = caregivers
                if let currentID = self.currentCaregiver?.id,
                   let updatedCaregiver = caregivers.first(where: { $0.id == currentID }) {
                    self.currentCaregiver = updatedCaregiver
                }
            },
            onError: { [weak self] error in
                self?.errorMessage = error.localizedDescription
            }
        )
        service.observeRoutines(
            householdID: session.household.id,
            onChange: { [weak self] routines in
                self?.routines = routines
            },
            onError: { [weak self] error in
                self?.errorMessage = error.localizedDescription
            }
        )
    }

    private func calendar(for household: Household) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: household.timeZoneIdentifier) ?? .current
        return calendar
    }

    private func loadPetPhoto(for householdID: String) {
        do {
            petPhotoData = try Data(contentsOf: petPhotoURL(for: householdID))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            petPhotoData = nil
        } catch {
            petPhotoData = nil
        }
    }

    private func petPhotoURL(for householdID: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let safeHouseholdID = Data(householdID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directory
            .appendingPathComponent("PetPhotos", isDirectory: true)
            .appendingPathComponent("\(safeHouseholdID).jpg", isDirectory: false)
    }

    private func occurrenceID(
        for routine: CareRoutine,
        on date: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%@_%04d-%02d-%02d",
            routine.id,
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func dueTime(
        for routine: CareRoutine,
        on day: Date,
        calendar: Calendar
    ) -> Date? {
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
