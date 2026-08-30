import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

@MainActor
final class FirebaseCareService: CareService {
    private enum Constants {
        static let householdIDDefaultsKey = "copaw.activeHouseholdID"
        static let inviteCodeLength = 6
        static let inviteCodeCharacters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        static let inviteCodeAttempts = 5
        static let collisionErrorDomain = "com.copaw.invite-code-collision"
        static let serviceErrorDomain = "com.copaw.care-service"
    }

    private let defaults: UserDefaults
    private var householdListener: ListenerRegistration?
    private var taskListener: ListenerRegistration?
    private var caregiverListener: ListenerRegistration?
    private var routineListener: ListenerRegistration?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restoreSession() async throws -> CareSession? {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()

        guard let householdID = defaults.string(forKey: Constants.householdIDDefaultsKey) else {
            return nil
        }

        do {
            async let householdDocument = householdReference(householdID).getDocument()
            async let memberDocument = memberReference(
                householdID: householdID,
                userID: user.uid
            ).getDocument()

            let (household, member) = try await (householdDocument, memberDocument)
            guard household.exists, member.exists else {
                clearSavedHousehold()
                return nil
            }

            return CareSession(
                household: try FirebaseModels.household(from: household),
                caregiver: try FirebaseModels.caregiver(from: member)
            )
        } catch {
            let nsError = error as NSError
            #if DEBUG
            NSLog("[FirebaseCareService] restoreSession failed domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
            #endif
            throw map(error)
        }
    }

    func createHousehold(
        name: String,
        petName: String,
        caregiverName: String
    ) async throws -> CareSession {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        let householdReference = database.collection("households").document()
        let timeZoneIdentifier = TimeZone.current.identifier

        for _ in 0..<Constants.inviteCodeAttempts {
            let inviteCode = Self.makeInviteCode()
            let inviteReference = database.collection("inviteCodes").document(inviteCode)
            let memberReference = householdReference.collection("members").document(user.uid)

            do {
                _ = try await database.runTransaction { transaction, errorPointer in
                    do {
                        let existingInvite = try transaction.getDocument(inviteReference)
                        guard !existingInvite.exists else {
                            errorPointer?.pointee = NSError(
                                domain: Constants.collisionErrorDomain,
                                code: 1
                            )
                            return nil
                        }

                        transaction.setData(
                            FirebaseModels.householdData(
                                id: householdReference.documentID,
                                name: name,
                                petName: petName,
                                inviteCode: inviteCode,
                                timeZoneIdentifier: timeZoneIdentifier,
                                ownerID: user.uid
                            ),
                            forDocument: householdReference
                        )
                        transaction.setData(
                            FirebaseModels.caregiverData(
                                id: user.uid,
                                displayName: caregiverName,
                                inviteCode: inviteCode
                            ),
                            forDocument: memberReference
                        )
                        transaction.setData(
                            [
                                "householdID": householdReference.documentID,
                                "createdBy": user.uid,
                                "createdAt": FieldValue.serverTimestamp(),
                                "active": true
                            ],
                            forDocument: inviteReference
                        )
                        return nil
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }
                }

                let household = Household(
                    id: householdReference.documentID,
                    name: name,
                    inviteCode: inviteCode,
                    petName: petName,
                    timeZoneIdentifier: timeZoneIdentifier
                )
                let caregiver = Caregiver(id: user.uid, displayName: caregiverName)
                save(householdID: household.id)
                return CareSession(household: household, caregiver: caregiver)
            } catch {
                let nsError = error as NSError
                if nsError.domain == Constants.collisionErrorDomain {
                    continue
                }
                throw map(error)
            }
        }

        throw CareServiceError.inviteCodeUnavailable
    }

    func joinHousehold(
        inviteCode: String,
        caregiverName: String
    ) async throws -> CareSession {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        let normalizedCode = Self.normalize(inviteCode)

        guard
            normalizedCode.count == Constants.inviteCodeLength,
            normalizedCode.allSatisfy(Constants.inviteCodeCharacters.contains)
        else {
            throw CareServiceError.invalidInviteCode
        }

        do {
            let inviteDocument = try await database
                .collection("inviteCodes")
                .document(normalizedCode)
                .getDocument()

            guard
                inviteDocument.exists,
                let inviteData = inviteDocument.data(),
                inviteData["active"] as? Bool != false,
                let householdID = inviteData["householdID"] as? String
            else {
                throw CareServiceError.invalidInviteCode
            }

            let memberReference = memberReference(
                householdID: householdID,
                userID: user.uid
            )
            let memberDocument = try await memberReference.getDocument()

            if memberDocument.exists {
                try await memberReference.updateData([
                    "displayName": caregiverName,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            } else {
                try await memberReference.setData(
                    FirebaseModels.caregiverData(
                        id: user.uid,
                        displayName: caregiverName,
                        inviteCode: normalizedCode
                    )
                )
            }

            let householdDocument = try await householdReference(householdID).getDocument()
            guard householdDocument.exists else {
                throw CareServiceError.invalidInviteCode
            }

            let household = try FirebaseModels.household(from: householdDocument)
            let caregiver = Caregiver(id: user.uid, displayName: caregiverName)
            save(householdID: household.id)
            return CareSession(household: household, caregiver: caregiver)
        } catch {
            throw map(error)
        }
    }

    func observeHousehold(
        householdID: String,
        onChange: @escaping (Household) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        do {
            try ensureFirebaseConfigured()
        } catch {
            onError(error)
            return
        }

        householdListener?.remove()
        householdListener = householdReference(householdID)
            .addSnapshotListener { snapshot, error in
                Task { @MainActor in
                    if let error {
                        onError(Self.mapFirebaseError(error))
                        return
                    }
                    guard let snapshot, snapshot.exists else {
                        onError(CareServiceError.householdMismatch)
                        return
                    }
                    do {
                        onChange(try FirebaseModels.household(from: snapshot))
                    } catch {
                        onError(error)
                    }
                }
            }
    }

    func observeTasks(
        householdID: String,
        onChange: @escaping ([CareTask]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        do {
            try ensureFirebaseConfigured()
        } catch {
            onError(error)
            return
        }

        taskListener?.remove()
        taskListener = householdReference(householdID)
            .collection("tasks")
            .addSnapshotListener { snapshot, error in
                Task { @MainActor in
                    if let error {
                        onError(Self.mapFirebaseError(error))
                        return
                    }
                    guard let snapshot else {
                        onError(CareServiceError.backendUnavailable)
                        return
                    }
                    do {
                        onChange(try snapshot.documents.map(FirebaseModels.task(from:)))
                    } catch {
                        onError(error)
                    }
                }
            }
    }

    func observeCaregivers(
        householdID: String,
        onChange: @escaping ([Caregiver]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        do {
            try ensureFirebaseConfigured()
        } catch {
            onError(error)
            return
        }

        caregiverListener?.remove()
        caregiverListener = householdReference(householdID)
            .collection("members")
            .addSnapshotListener { snapshot, error in
                Task { @MainActor in
                    if let error {
                        onError(Self.mapFirebaseError(error))
                        return
                    }
                    guard let snapshot else {
                        onError(CareServiceError.backendUnavailable)
                        return
                    }
                    do {
                        onChange(try snapshot.documents.map(FirebaseModels.caregiver(from:)))
                    } catch {
                        onError(error)
                    }
                }
            }
    }

    func observeRoutines(
        householdID: String,
        onChange: @escaping ([CareRoutine]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        do {
            try ensureFirebaseConfigured()
        } catch {
            onError(error)
            return
        }

        routineListener?.remove()
        routineListener = householdReference(householdID)
            .collection("routines")
            .addSnapshotListener { snapshot, error in
                Task { @MainActor in
                    if let error {
                        onError(Self.mapFirebaseError(error))
                        return
                    }
                    guard let snapshot else {
                        onError(CareServiceError.backendUnavailable)
                        return
                    }
                    do {
                        onChange(try snapshot.documents.map(FirebaseModels.routine(from:)))
                    } catch {
                        onError(error)
                    }
                }
            }
    }

    func addTask(_ task: CareTask, householdID: String) async throws {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        guard task.kind == .oneOff,
              task.status == .unclaimed,
              task.createdByID == user.uid else {
            throw CareServiceError.invalidTransition
        }

        do {
            try await taskReference(householdID: householdID, taskID: task.id).setData(
                FirebaseModels.taskData(
                    task,
                    createdByID: user.uid,
                    useServerCreatedAt: true
                )
            )
        } catch {
            throw map(error)
        }
    }

    func addRoutine(_ routine: CareRoutine, householdID: String) async throws {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        guard routine.createdByID == user.uid else {
            throw CareServiceError.notHouseholdMember
        }

        do {
            try await routineReference(householdID: householdID, routineID: routine.id)
                .setData(FirebaseModels.routineData(routine))
        } catch {
            throw map(error)
        }
    }

    func updateProfile(
        household: Household,
        caregiver: Caregiver
    ) async throws {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        try validate(caregiver: caregiver, userID: user.uid)

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

        let batch = database.batch()
        batch.updateData(
            [
                "name": householdName,
                "petName": petName,
                "updatedAt": FieldValue.serverTimestamp()
            ],
            forDocument: householdReference(household.id)
        )
        batch.updateData(
            [
                "displayName": caregiverName,
                "updatedAt": FieldValue.serverTimestamp()
            ],
            forDocument: memberReference(householdID: household.id, userID: user.uid)
        )

        do {
            try await batch.commit()
        } catch {
            throw map(error)
        }
    }

    func claimTask(
        _ task: CareTask,
        householdID: String,
        caregiver: Caregiver
    ) async throws {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        try validate(caregiver: caregiver, userID: user.uid)
        let reference = taskReference(householdID: householdID, taskID: task.id)

        do {
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    let document = try transaction.getDocument(reference)
                    if document.exists, let data = document.data() {
                        try Self.requireUnclaimed(data)
                        var update: [String: Any] = [
                            "status": CareTaskStatus.claimed.rawValue,
                            "assigneeID": user.uid,
                            "assigneeName": caregiver.displayName,
                            "claimedAt": FieldValue.serverTimestamp(),
                            "revision": Self.revision(data) + 1
                        ]
                        update.merge(FirebaseModels.clearedAssignmentRequest) { _, new in new }
                        transaction.updateData(update, forDocument: reference)
                    } else {
                        guard task.kind == .routine, let createdByID = task.createdByID else {
                            throw CareServiceError.taskNotFound
                        }
                        var materialized = task
                        materialized.status = .claimed
                        materialized.assignmentRequest = nil
                        materialized.assigneeID = user.uid
                        materialized.assigneeNameSnapshot = caregiver.displayName
                        materialized.revision += 1
                        var payload = FirebaseModels.taskData(
                            materialized,
                            createdByID: createdByID,
                            useServerCreatedAt: false
                        )
                        payload["claimedAt"] = FieldValue.serverTimestamp()
                        transaction.setData(payload, forDocument: reference)
                    }
                    return nil
                } catch {
                    errorPointer?.pointee = Self.serviceNSError(error)
                    return nil
                }
            }
        } catch {
            throw map(error)
        }
    }

    func requestAssignment(
        for task: CareTask,
        householdID: String,
        requester: Caregiver,
        requestedCaregiver: Caregiver
    ) async throws {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        try validate(caregiver: requester, userID: user.uid)
        guard requester.id != requestedCaregiver.id else {
            throw CareServiceError.cannotRequestSelf
        }

        let reference = taskReference(householdID: householdID, taskID: task.id)
        let requesterReference = memberReference(householdID: householdID, userID: user.uid)
        let recipientReference = memberReference(
            householdID: householdID,
            userID: requestedCaregiver.id
        )
        let requestID = UUID().uuidString

        do {
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    let requesterDocument = try transaction.getDocument(requesterReference)
                    let recipientDocument = try transaction.getDocument(recipientReference)
                    let taskDocument = try transaction.getDocument(reference)

                    guard
                        requesterDocument.exists,
                        let requesterName = requesterDocument.data()?["displayName"] as? String
                    else {
                        throw CareServiceError.notHouseholdMember
                    }
                    guard
                        recipientDocument.exists,
                        let recipientName = recipientDocument.data()?["displayName"] as? String
                    else {
                        throw CareServiceError.caregiverNotFound
                    }

                    let requestData: [String: Any] = [
                        "assignmentRequestID": requestID,
                        "assignmentMode": AssignmentMode.direct.rawValue,
                        "requestedByID": user.uid,
                        "requestedByName": requesterName,
                        "requestedToID": requestedCaregiver.id,
                        "requestedToName": recipientName,
                        "assignmentRequestedAt": FieldValue.serverTimestamp()
                    ]

                    if taskDocument.exists, let data = taskDocument.data() {
                        try Self.requireUnclaimed(data)
                        guard data["assignmentRequestID"] is NSNull
                                || data["assignmentRequestID"] == nil else {
                            throw CareServiceError.assignmentRequestChanged
                        }
                        var update = requestData
                        update["revision"] = Self.revision(data) + 1
                        transaction.updateData(update, forDocument: reference)
                    } else {
                        guard task.kind == .routine, let createdByID = task.createdByID else {
                            throw CareServiceError.taskNotFound
                        }
                        var materialized = task
                        materialized.assignmentRequest = AssignmentRequest(
                            id: requestID,
                            requestedByID: user.uid,
                            requestedByNameSnapshot: requesterName,
                            requestedToID: requestedCaregiver.id,
                            requestedToNameSnapshot: recipientName,
                            mode: .direct,
                            createdAt: Date()
                        )
                        materialized.revision += 1
                        var payload = FirebaseModels.taskData(
                            materialized,
                            createdByID: createdByID,
                            useServerCreatedAt: false
                        )
                        payload["assignmentRequestedAt"] = FieldValue.serverTimestamp()
                        transaction.setData(payload, forDocument: reference)
                    }
                    return nil
                } catch {
                    errorPointer?.pointee = Self.serviceNSError(error)
                    return nil
                }
            }
        } catch {
            throw map(error)
        }
    }

    func requestOpenAssignment(
        for task: CareTask,
        householdID: String,
        requester: Caregiver
    ) async throws {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        try validate(caregiver: requester, userID: user.uid)

        let reference = taskReference(householdID: householdID, taskID: task.id)
        let requesterReference = memberReference(householdID: householdID, userID: user.uid)
        let requestID = UUID().uuidString

        do {
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    let requesterDocument = try transaction.getDocument(requesterReference)
                    let taskDocument = try transaction.getDocument(reference)
                    guard
                        requesterDocument.exists,
                        let requesterName = requesterDocument.data()?["displayName"] as? String
                    else {
                        throw CareServiceError.notHouseholdMember
                    }

                    let requestData: [String: Any] = [
                        "assignmentRequestID": requestID,
                        "assignmentMode": AssignmentMode.open.rawValue,
                        "requestedByID": user.uid,
                        "requestedByName": requesterName,
                        "requestedToID": NSNull(),
                        "requestedToName": NSNull(),
                        "assignmentRequestedAt": FieldValue.serverTimestamp()
                    ]

                    if taskDocument.exists, let data = taskDocument.data() {
                        try Self.requireUnclaimed(data)
                        guard data["assignmentRequestID"] is NSNull
                                || data["assignmentRequestID"] == nil else {
                            throw CareServiceError.assignmentRequestChanged
                        }
                        var update = requestData
                        update["revision"] = Self.revision(data) + 1
                        transaction.updateData(update, forDocument: reference)
                    } else {
                        guard task.kind == .routine, let createdByID = task.createdByID else {
                            throw CareServiceError.taskNotFound
                        }
                        var materialized = task
                        materialized.assignmentRequest = AssignmentRequest(
                            id: requestID,
                            requestedByID: user.uid,
                            requestedByNameSnapshot: requesterName,
                            requestedToID: nil,
                            requestedToNameSnapshot: nil,
                            mode: .open,
                            createdAt: Date()
                        )
                        materialized.revision += 1
                        var payload = FirebaseModels.taskData(
                            materialized,
                            createdByID: createdByID,
                            useServerCreatedAt: false
                        )
                        payload["assignmentRequestedAt"] = FieldValue.serverTimestamp()
                        transaction.setData(payload, forDocument: reference)
                    }
                    return nil
                } catch {
                    errorPointer?.pointee = Self.serviceNSError(error)
                    return nil
                }
            }
        } catch {
            throw map(error)
        }
    }

    func acceptAssignmentRequest(
        taskID: String,
        requestID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        try validate(caregiver: caregiver, userID: user.uid)
        let reference = taskReference(householdID: householdID, taskID: taskID)

        try await mutateRequest(reference: reference) { data in
            try Self.requireMatchingRequest(data, requestID: requestID)
            guard data["requestedToID"] as? String == user.uid else {
                throw CareServiceError.notRequestRecipient
            }
            var update: [String: Any] = [
                "status": CareTaskStatus.claimed.rawValue,
                "assigneeID": user.uid,
                "assigneeName": caregiver.displayName,
                "claimedAt": FieldValue.serverTimestamp(),
                "revision": Self.revision(data) + 1
            ]
            update.merge(FirebaseModels.clearedAssignmentRequest) { _, new in new }
            return update
        }
    }

    func declineAssignmentRequest(
        taskID: String,
        requestID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        try validate(caregiver: caregiver, userID: user.uid)
        let reference = taskReference(householdID: householdID, taskID: taskID)

        try await mutateRequest(reference: reference) { data in
            try Self.requireMatchingRequest(data, requestID: requestID)
            guard data["requestedToID"] as? String == user.uid else {
                throw CareServiceError.notRequestRecipient
            }
            var update = FirebaseModels.clearedAssignmentRequest
            update["revision"] = Self.revision(data) + 1
            return update
        }
    }

    func cancelAssignmentRequest(
        taskID: String,
        requestID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        try validate(caregiver: caregiver, userID: user.uid)
        let reference = taskReference(householdID: householdID, taskID: taskID)

        try await mutateRequest(reference: reference) { data in
            try Self.requireMatchingRequest(data, requestID: requestID)
            guard data["requestedByID"] as? String == user.uid else {
                throw CareServiceError.notRequestOwner
            }
            var update = FirebaseModels.clearedAssignmentRequest
            update["revision"] = Self.revision(data) + 1
            return update
        }
    }

    func completeTask(
        taskID: String,
        householdID: String,
        caregiver: Caregiver
    ) async throws {
        try ensureFirebaseConfigured()
        let user = try await ensureAuthenticated()
        try validate(caregiver: caregiver, userID: user.uid)
        let reference = taskReference(householdID: householdID, taskID: taskID)

        do {
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    let document = try transaction.getDocument(reference)
                    guard document.exists, let data = document.data() else {
                        throw CareServiceError.taskNotFound
                    }
                    guard Self.status(data) == .claimed else {
                        if Self.status(data) == .completed {
                            throw CareServiceError.taskAlreadyCompleted
                        }
                        throw CareServiceError.taskNotClaimed
                    }
                    guard data["assigneeID"] as? String == user.uid else {
                        throw CareServiceError.notAssignee
                    }

                    transaction.updateData(
                        [
                            "status": CareTaskStatus.completed.rawValue,
                            "completedBy": caregiver.displayName,
                            "completedByID": user.uid,
                            "completedAt": FieldValue.serverTimestamp(),
                            "revision": Self.revision(data) + 1
                        ],
                        forDocument: reference
                    )
                    return nil
                } catch {
                    errorPointer?.pointee = Self.serviceNSError(error)
                    return nil
                }
            }
        } catch {
            throw map(error)
        }
    }

    func stopObserving() {
        householdListener?.remove()
        taskListener?.remove()
        caregiverListener?.remove()
        routineListener?.remove()
        householdListener = nil
        taskListener = nil
        caregiverListener = nil
        routineListener = nil
    }

    func leaveHousehold() {
        stopObserving()
        clearSavedHousehold()
    }

    private func mutateRequest(
        reference: DocumentReference,
        update: @escaping ([String: Any]) throws -> [String: Any]
    ) async throws {
        do {
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    let document = try transaction.getDocument(reference)
                    guard document.exists, let data = document.data() else {
                        throw CareServiceError.taskNotFound
                    }
                    try Self.requireUnclaimed(data)
                    transaction.updateData(try update(data), forDocument: reference)
                    return nil
                } catch {
                    errorPointer?.pointee = Self.serviceNSError(error)
                    return nil
                }
            }
        } catch {
            throw map(error)
        }
    }

    private var database: Firestore {
        Firestore.firestore()
    }

    private func ensureFirebaseConfigured() throws {
        guard FirebaseApp.app() != nil else {
            throw CareServiceError.firebaseNotConfigured
        }
    }

    private func ensureAuthenticated() async throws -> User {
        if let user = Auth.auth().currentUser {
            #if DEBUG
            NSLog("[FirebaseCareService] using current Firebase auth session")
            #endif
            return user
        }
        do {
            let user = try await Auth.auth().signInAnonymously().user
            #if DEBUG
            NSLog("[FirebaseCareService] anonymous auth succeeded")
            #endif
            return user
        } catch {
            let nsError = error as NSError
            #if DEBUG
            NSLog("[FirebaseCareService] anonymous auth failed domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
            #endif
            let mappedError = Self.mapFirebaseError(error)
            throw mappedError
        }
    }

    private func validate(caregiver: Caregiver, userID: String) throws {
        guard caregiver.id == userID else {
            throw CareServiceError.notHouseholdMember
        }
    }

    private func householdReference(_ householdID: String) -> DocumentReference {
        database.collection("households").document(householdID)
    }

    private func memberReference(householdID: String, userID: String) -> DocumentReference {
        householdReference(householdID).collection("members").document(userID)
    }

    private func routineReference(householdID: String, routineID: String) -> DocumentReference {
        householdReference(householdID).collection("routines").document(routineID)
    }

    private func taskReference(householdID: String, taskID: String) -> DocumentReference {
        householdReference(householdID).collection("tasks").document(taskID)
    }

    private func save(householdID: String) {
        defaults.set(householdID, forKey: Constants.householdIDDefaultsKey)
    }

    private func clearSavedHousehold() {
        defaults.removeObject(forKey: Constants.householdIDDefaultsKey)
    }

    private func map(_ error: Error) -> Error {
        if let serviceError = error as? CareServiceError {
            return serviceError
        }
        return Self.mapFirebaseError(error)
    }

    private static func normalize(_ inviteCode: String) -> String {
        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func makeInviteCode() -> String {
        String(
            (0..<Constants.inviteCodeLength).compactMap { _ in
                Constants.inviteCodeCharacters.randomElement()
            }
        )
    }

    private static func status(_ data: [String: Any]) -> CareTaskStatus? {
        switch data["status"] as? String {
        case "pending", CareTaskStatus.unclaimed.rawValue: .unclaimed
        case CareTaskStatus.claimed.rawValue: .claimed
        case CareTaskStatus.completed.rawValue: .completed
        default: nil
        }
    }

    private static func revision(_ data: [String: Any]) -> Int {
        if let value = data["revision"] as? Int { return value }
        return (data["revision"] as? NSNumber)?.intValue ?? 0
    }

    private static func requireUnclaimed(_ data: [String: Any]) throws {
        switch status(data) {
        case .unclaimed:
            return
        case .claimed:
            throw CareServiceError.taskAlreadyClaimed(
                assigneeName: data["assigneeName"] as? String
            )
        case .completed:
            throw CareServiceError.taskAlreadyCompleted
        case nil:
            throw CareServiceError.invalidTransition
        }
    }

    private static func requireMatchingRequest(
        _ data: [String: Any],
        requestID: String
    ) throws {
        guard data["assignmentRequestID"] as? String == requestID else {
            throw CareServiceError.assignmentRequestChanged
        }
    }

    private static func serviceNSError(_ error: Error) -> NSError {
        guard let serviceError = error as? CareServiceError else {
            return error as NSError
        }

        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: serviceError.localizedDescription
        ]
        if case let .taskAlreadyClaimed(assigneeName) = serviceError,
           let assigneeName {
            userInfo["assigneeName"] = assigneeName
        }
        return NSError(
            domain: Constants.serviceErrorDomain,
            code: serviceErrorCode(serviceError),
            userInfo: userInfo
        )
    }

    private static func serviceErrorCode(_ error: CareServiceError) -> Int {
        switch error {
        case .taskNotFound: 1
        case .taskAlreadyCompleted: 2
        case .taskAlreadyClaimed: 3
        case .taskNotClaimed: 4
        case .notAssignee: 5
        case .assignmentRequestChanged: 6
        case .notRequestRecipient: 7
        case .notRequestOwner: 8
        case .invalidTransition: 9
        case .caregiverNotFound: 10
        case .notHouseholdMember: 11
        default: 0
        }
    }

    private static func mapFirebaseError(_ error: Error) -> Error {
        if let serviceError = error as? CareServiceError {
            return serviceError
        }

        let nsError = error as NSError
        if nsError.domain == Constants.serviceErrorDomain {
            switch nsError.code {
            case 1: return CareServiceError.taskNotFound
            case 2: return CareServiceError.taskAlreadyCompleted
            case 3:
                return CareServiceError.taskAlreadyClaimed(
                    assigneeName: nsError.userInfo["assigneeName"] as? String
                )
            case 4: return CareServiceError.taskNotClaimed
            case 5: return CareServiceError.notAssignee
            case 6: return CareServiceError.assignmentRequestChanged
            case 7: return CareServiceError.notRequestRecipient
            case 8: return CareServiceError.notRequestOwner
            case 9: return CareServiceError.invalidTransition
            case 10: return CareServiceError.caregiverNotFound
            case 11: return CareServiceError.notHouseholdMember
            default: return CareServiceError.backendUnavailable
            }
        }

        if nsError.domain == NSURLErrorDomain
            || (nsError.domain.contains("Auth") && nsError.code == 17020)
            || (nsError.domain.contains("Firestore") && [4, 14].contains(nsError.code)) {
            return CareServiceError.networkUnavailable
        }
        if nsError.domain.contains("Firestore") && nsError.code == 7 {
            return CareServiceError.permissionDenied
        }
        return CareServiceError.backendUnavailable
    }
}
