import FirebaseFirestore
import Foundation

enum FirebaseModels {
    static func household(from document: DocumentSnapshot) throws -> Household {
        guard
            let data = document.data(),
            let name = data["name"] as? String,
            let inviteCode = data["inviteCode"] as? String,
            let petName = data["petName"] as? String
        else {
            throw CareServiceError.malformedData
        }

        return Household(
            id: document.documentID,
            name: name,
            inviteCode: inviteCode,
            petName: petName,
            timeZoneIdentifier: data["timeZoneIdentifier"] as? String
                ?? TimeZone.current.identifier
        )
    }

    static func caregiver(from document: DocumentSnapshot) throws -> Caregiver {
        guard
            let data = document.data(),
            let displayName = data["displayName"] as? String
        else {
            throw CareServiceError.malformedData
        }

        return Caregiver(id: document.documentID, displayName: displayName)
    }

    static func routine(from document: DocumentSnapshot) throws -> CareRoutine {
        guard
            let data = document.data(),
            let title = data["title"] as? String,
            let categoryValue = data["category"] as? String,
            let category = CareCategory(rawValue: categoryValue),
            let priorityValue = data["priority"] as? String,
            let priority = CarePriority(rawValue: priorityValue),
            let hour = integer(data["hour"]),
            let minute = integer(data["minute"]),
            let startDate = (data["startDate"] as? Timestamp)?.dateValue(),
            let timeZoneIdentifier = data["timeZoneIdentifier"] as? String,
            let createdByID = data["createdByID"] as? String,
            let createdByName = data["createdByName"] as? String,
            let isActive = data["isActive"] as? Bool
        else {
            throw CareServiceError.malformedData
        }

        return CareRoutine(
            id: document.documentID,
            title: title,
            category: category,
            priority: priority,
            frequency: (data["frequency"] as? String).flatMap(CareRoutineFrequency.init(rawValue:)) ?? .daily,
            weekdays: (data["weekdays"] as? [Int]) ?? Array(1...7),
            hour: hour,
            minute: minute,
            startDate: startDate,
            timeZoneIdentifier: timeZoneIdentifier,
            createdByID: createdByID,
            createdByNameSnapshot: createdByName,
            isActive: isActive
        )
    }

    static func task(from document: DocumentSnapshot) throws -> CareTask {
        guard
            let data = document.data(),
            let title = data["title"] as? String,
            let categoryValue = data["category"] as? String,
            let category = CareCategory(rawValue: categoryValue),
            let dueTime = (data["dueTime"] as? Timestamp)?.dateValue(),
            let statusValue = data["status"] as? String,
            let status = taskStatus(statusValue),
            let createdBy = data["createdBy"] as? String
        else {
            throw CareServiceError.malformedData
        }

        let assignmentRequest: AssignmentRequest?
        if let requestID = data["assignmentRequestID"] as? String,
           let requestedByID = data["requestedByID"] as? String,
           let requestedByName = data["requestedByName"] as? String,
           let requestedAt = (data["assignmentRequestedAt"] as? Timestamp)?.dateValue() {
            let requestedToID = data["requestedToID"] as? String
            let requestedToName = data["requestedToName"] as? String
            assignmentRequest = AssignmentRequest(
                id: requestID,
                requestedByID: requestedByID,
                requestedByNameSnapshot: requestedByName,
                requestedToID: requestedToID,
                requestedToNameSnapshot: requestedToName,
                mode: (data["assignmentMode"] as? String).flatMap(AssignmentMode.init(rawValue:))
                    ?? (requestedToID == nil ? .open : .direct),
                createdAt: requestedAt
            )
        } else {
            assignmentRequest = nil
        }

        return CareTask(
            id: document.documentID,
            title: title,
            category: category,
            dueTime: dueTime,
            kind: (data["kind"] as? String).flatMap(CareTaskKind.init(rawValue:)) ?? .oneOff,
            priority: (data["priority"] as? String).flatMap(CarePriority.init(rawValue:)) ?? .normal,
            routineID: data["routineID"] as? String,
            status: status,
            assignmentRequest: assignmentRequest,
            assigneeID: data["assigneeID"] as? String,
            assigneeNameSnapshot: data["assigneeName"] as? String,
            claimedAt: (data["claimedAt"] as? Timestamp)?.dateValue(),
            createdByID: data["createdByID"] as? String,
            createdBy: createdBy,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? dueTime,
            completedByID: data["completedByID"] as? String,
            completedBy: data["completedBy"] as? String,
            completedAt: (data["completedAt"] as? Timestamp)?.dateValue(),
            revision: integer(data["revision"]) ?? 0
        )
    }

    static func householdData(
        id: String,
        name: String,
        petName: String,
        inviteCode: String,
        timeZoneIdentifier: String,
        ownerID: String
    ) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "petName": petName,
            "inviteCode": inviteCode,
            "timeZoneIdentifier": timeZoneIdentifier,
            "ownerID": ownerID,
            "createdAt": FieldValue.serverTimestamp()
        ]
    }

    static func caregiverData(
        id: String,
        displayName: String,
        inviteCode: String
    ) -> [String: Any] {
        [
            "id": id,
            "displayName": displayName,
            "inviteCode": inviteCode,
            "joinedAt": FieldValue.serverTimestamp()
        ]
    }

    static func routineData(_ routine: CareRoutine) -> [String: Any] {
        [
            "id": routine.id,
            "title": routine.title,
            "category": routine.category.rawValue,
            "priority": routine.priority.rawValue,
            "frequency": routine.frequency.rawValue,
            "weekdays": routine.weekdays,
            "hour": routine.hour,
            "minute": routine.minute,
            "startDate": Timestamp(date: routine.startDate),
            "timeZoneIdentifier": routine.timeZoneIdentifier,
            "createdByID": routine.createdByID,
            "createdByName": routine.createdByNameSnapshot,
            "isActive": routine.isActive,
            "createdAt": FieldValue.serverTimestamp()
        ]
    }

    static func taskData(
        _ task: CareTask,
        createdByID: String,
        useServerCreatedAt: Bool
    ) -> [String: Any] {
        var data: [String: Any] = [
            "id": task.id,
            "title": task.title,
            "category": task.category.rawValue,
            "dueTime": Timestamp(date: task.dueTime),
            "kind": task.kind.rawValue,
            "priority": task.priority.rawValue,
            "routineID": task.routineID as Any? ?? NSNull(),
            "status": task.status.rawValue,
            "assignmentRequestID": task.assignmentRequest?.id as Any? ?? NSNull(),
            "assignmentMode": task.assignmentRequest?.mode.rawValue as Any? ?? NSNull(),
            "requestedByID": task.assignmentRequest?.requestedByID as Any? ?? NSNull(),
            "requestedByName": task.assignmentRequest?.requestedByNameSnapshot as Any? ?? NSNull(),
            "requestedToID": task.assignmentRequest?.requestedToID as Any? ?? NSNull(),
            "requestedToName": task.assignmentRequest?.requestedToNameSnapshot as Any? ?? NSNull(),
            "assignmentRequestedAt": task.assignmentRequest
                .map { Timestamp(date: $0.createdAt) } as Any? ?? NSNull(),
            "assigneeID": task.assigneeID as Any? ?? NSNull(),
            "assigneeName": task.assigneeNameSnapshot as Any? ?? NSNull(),
            "claimedAt": task.claimedAt.map(Timestamp.init(date:)) as Any? ?? NSNull(),
            "createdByID": createdByID,
            "createdBy": task.createdBy,
            "completedByID": task.completedByID as Any? ?? NSNull(),
            "completedBy": task.completedBy as Any? ?? NSNull(),
            "completedAt": task.completedAt.map(Timestamp.init(date:)) as Any? ?? NSNull(),
            "revision": task.revision
        ]
        data["createdAt"] = useServerCreatedAt
            ? FieldValue.serverTimestamp()
            : Timestamp(date: task.createdAt)
        return data
    }

    static var clearedAssignmentRequest: [String: Any] {
        [
            "assignmentRequestID": NSNull(),
            "assignmentMode": NSNull(),
            "requestedByID": NSNull(),
            "requestedByName": NSNull(),
            "requestedToID": NSNull(),
            "requestedToName": NSNull(),
            "assignmentRequestedAt": NSNull()
        ]
    }

    private static func taskStatus(_ value: String) -> CareTaskStatus? {
        switch value {
        case "pending", CareTaskStatus.unclaimed.rawValue: .unclaimed
        case CareTaskStatus.claimed.rawValue: .claimed
        case CareTaskStatus.completed.rawValue: .completed
        default: nil
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }
}
