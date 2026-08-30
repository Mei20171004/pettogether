import Foundation

struct Household: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var inviteCode: String
    var petName: String
    var timeZoneIdentifier: String

    init(
        id: String,
        name: String,
        inviteCode: String,
        petName: String,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.petName = petName
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, inviteCode, petName, timeZoneIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        inviteCode = try container.decode(String.self, forKey: .inviteCode)
        petName = try container.decode(String.self, forKey: .petName)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
            ?? TimeZone.current.identifier
    }
}

struct Caregiver: Identifiable, Codable, Equatable {
    let id: String
    var displayName: String
}

enum CareTaskStatus: String, Codable, CaseIterable {
    case unclaimed
    case claimed
    case completed

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "pending", Self.unclaimed.rawValue:
            self = .unclaimed
        case Self.claimed.rawValue:
            self = .claimed
        case Self.completed.rawValue:
            self = .completed
        default:
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown care task status: \(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

}

enum CareTaskKind: String, Codable, CaseIterable, Identifiable {
    case routine
    case oneOff

    var id: String { rawValue }
}

enum CarePriority: String, Codable, CaseIterable, Identifiable {
    case normal
    case urgent

    var id: String { rawValue }
}

enum CareCategory: String, Codable, CaseIterable, Identifiable {
    case feeding
    case walking
    case medication
    case grooming
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feeding: "Feeding"
        case .walking: "Walking"
        case .medication: "Medication"
        case .grooming: "Grooming"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .feeding: "fork.knife"
        case .walking: "figure.walk"
        case .medication: "pills.fill"
        case .grooming: "sparkles"
        case .other: "pawprint.fill"
        }
    }
}

struct AssignmentRequest: Identifiable, Codable, Equatable {
    let id: String
    let requestedByID: String
    let requestedByNameSnapshot: String
    let requestedToID: String?
    let requestedToNameSnapshot: String?
    let mode: AssignmentMode
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, requestedByID, requestedByNameSnapshot, requestedToID
        case requestedToNameSnapshot, mode, createdAt
    }

    init(
        id: String,
        requestedByID: String,
        requestedByNameSnapshot: String,
        requestedToID: String?,
        requestedToNameSnapshot: String?,
        mode: AssignmentMode = .direct,
        createdAt: Date
    ) {
        self.id = id
        self.requestedByID = requestedByID
        self.requestedByNameSnapshot = requestedByNameSnapshot
        self.requestedToID = requestedToID
        self.requestedToNameSnapshot = requestedToNameSnapshot
        self.mode = mode
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        requestedByID = try container.decode(String.self, forKey: .requestedByID)
        requestedByNameSnapshot = try container.decode(String.self, forKey: .requestedByNameSnapshot)
        requestedToID = try container.decodeIfPresent(String.self, forKey: .requestedToID)
        requestedToNameSnapshot = try container.decodeIfPresent(String.self, forKey: .requestedToNameSnapshot)
        mode = try container.decodeIfPresent(AssignmentMode.self, forKey: .mode) ?? .direct
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

enum AssignmentMode: String, Codable {
    case direct
    case open
}

enum CareRoutineFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case selectedDays

    var id: String { rawValue }
}

struct CareRoutine: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var category: CareCategory
    var priority: CarePriority
    var frequency: CareRoutineFrequency
    var weekdays: [Int]
    var hour: Int
    var minute: Int
    var startDate: Date
    var timeZoneIdentifier: String
    var createdByID: String
    var createdByNameSnapshot: String
    var isActive: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title, category, priority, frequency, weekdays, hour, minute
        case startDate, timeZoneIdentifier, createdByID, createdByNameSnapshot, isActive
    }

    init(
        id: String,
        title: String,
        category: CareCategory,
        priority: CarePriority = .normal,
        frequency: CareRoutineFrequency = .daily,
        weekdays: [Int] = Array(1...7),
        hour: Int,
        minute: Int,
        startDate: Date,
        timeZoneIdentifier: String,
        createdByID: String,
        createdByNameSnapshot: String,
        isActive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.priority = priority
        self.frequency = frequency
        self.weekdays = weekdays
        self.hour = hour
        self.minute = minute
        self.startDate = startDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.createdByID = createdByID
        self.createdByNameSnapshot = createdByNameSnapshot
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(CareCategory.self, forKey: .category)
        priority = try container.decodeIfPresent(CarePriority.self, forKey: .priority) ?? .normal
        frequency = try container.decodeIfPresent(CareRoutineFrequency.self, forKey: .frequency) ?? .daily
        weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? Array(1...7)
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
        startDate = try container.decode(Date.self, forKey: .startDate)
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        createdByID = try container.decode(String.self, forKey: .createdByID)
        createdByNameSnapshot = try container.decode(String.self, forKey: .createdByNameSnapshot)
        isActive = try container.decode(Bool.self, forKey: .isActive)
    }
}

struct CareTask: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var category: CareCategory
    var dueTime: Date
    var kind: CareTaskKind
    var priority: CarePriority
    var routineID: String?
    var status: CareTaskStatus
    var assignmentRequest: AssignmentRequest?
    var assigneeID: String?
    var assigneeNameSnapshot: String?
    var claimedAt: Date?
    var createdByID: String?
    var createdBy: String
    var createdAt: Date
    var completedByID: String?
    var completedBy: String?
    var completedAt: Date?
    var revision: Int

    init(
        id: String,
        title: String,
        category: CareCategory,
        dueTime: Date,
        kind: CareTaskKind = .oneOff,
        priority: CarePriority = .normal,
        routineID: String? = nil,
        status: CareTaskStatus = .unclaimed,
        assignmentRequest: AssignmentRequest? = nil,
        assigneeID: String? = nil,
        assigneeNameSnapshot: String? = nil,
        claimedAt: Date? = nil,
        createdByID: String? = nil,
        createdBy: String,
        createdAt: Date? = nil,
        completedByID: String? = nil,
        completedBy: String? = nil,
        completedAt: Date? = nil,
        revision: Int = 0
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.dueTime = dueTime
        self.kind = kind
        self.priority = priority
        self.routineID = routineID
        self.status = status
        self.assignmentRequest = assignmentRequest
        self.assigneeID = assigneeID
        self.assigneeNameSnapshot = assigneeNameSnapshot
        self.claimedAt = claimedAt
        self.createdByID = createdByID
        self.createdBy = createdBy
        self.createdAt = createdAt ?? dueTime
        self.completedByID = completedByID
        self.completedBy = completedBy
        self.completedAt = completedAt
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, dueTime, kind, priority, routineID, status
        case assignmentRequest, assigneeID, assigneeNameSnapshot, claimedAt
        case createdByID, createdBy, createdAt, completedByID, completedBy, completedAt, revision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(CareCategory.self, forKey: .category)
        dueTime = try container.decode(Date.self, forKey: .dueTime)
        kind = try container.decodeIfPresent(CareTaskKind.self, forKey: .kind) ?? .oneOff
        priority = try container.decodeIfPresent(CarePriority.self, forKey: .priority) ?? .normal
        routineID = try container.decodeIfPresent(String.self, forKey: .routineID)
        status = try container.decode(CareTaskStatus.self, forKey: .status)
        assignmentRequest = try container.decodeIfPresent(AssignmentRequest.self, forKey: .assignmentRequest)
        assigneeID = try container.decodeIfPresent(String.self, forKey: .assigneeID)
        assigneeNameSnapshot = try container.decodeIfPresent(String.self, forKey: .assigneeNameSnapshot)
        claimedAt = try container.decodeIfPresent(Date.self, forKey: .claimedAt)
        createdByID = try container.decodeIfPresent(String.self, forKey: .createdByID)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? dueTime
        completedByID = try container.decodeIfPresent(String.self, forKey: .completedByID)
        completedBy = try container.decodeIfPresent(String.self, forKey: .completedBy)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }
}

struct CareSession: Equatable {
    let household: Household
    let caregiver: Caregiver
}
