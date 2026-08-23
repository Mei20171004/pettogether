/// Core domain models for copaw.
///
/// These mirror the Swift models in `co-paw/copaw/Models/Models.swift`.
/// Dates are serialized as epoch milliseconds in JSON and as Firestore
/// `Timestamp`s on the wire (see the service layer).
library;

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

int? _msFromJson(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _dateFromJson(dynamic value) {
  final ms = _msFromJson(value);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Serializes a [DateTime] to epoch milliseconds. Null-safe.
int? _dateToJson(DateTime? value) => value?.millisecondsSinceEpoch;

String? _stringFromJson(dynamic value) => value as String?;

int _intFromJson(dynamic value, [int fallback = 0]) =>
    value is int ? value : (value is num ? value.toInt() : fallback);

bool _boolFromJson(dynamic value, [bool fallback = false]) =>
    value is bool ? value : fallback;

List<int> _weekdaysFromJson(dynamic value) {
  if (value is List) {
    return value.whereType<num>().map((e) => e.toInt()).toList();
  }
  return List<int>.from(<int>[1, 2, 3, 4, 5, 6, 7]);
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum CareTaskStatus {
  unclaimed('unclaimed'),
  claimed('claimed'),
  completed('completed');

  const CareTaskStatus(this.rawValue);
  final String rawValue;

  /// Accepts the legacy "pending" value used by older documents.
  static CareTaskStatus fromRaw(String value) {
    switch (value) {
      case 'pending':
      case 'unclaimed':
        return CareTaskStatus.unclaimed;
      case 'claimed':
        return CareTaskStatus.claimed;
      case 'completed':
        return CareTaskStatus.completed;
      default:
        throw FormatException('Unknown care task status: $value');
    }
  }
}

enum CareTaskKind {
  routine('routine'),
  oneOff('oneOff');

  const CareTaskKind(this.rawValue);
  final String rawValue;

  static CareTaskKind fromRaw(String value) => CareTaskKind.values
      .firstWhere((e) => e.rawValue == value, orElse: () => CareTaskKind.oneOff);
}

enum CarePriority {
  normal('normal'),
  urgent('urgent');

  const CarePriority(this.rawValue);
  final String rawValue;

  static CarePriority fromRaw(String value) => CarePriority.values
      .firstWhere((e) => e.rawValue == value, orElse: () => CarePriority.normal);
}

/// The pet species a household cares for.
enum PetType {
  cat('cat'),
  dog('dog'),
  bird('bird'),
  rabbit('rabbit'),
  snake('snake');

  const PetType(this.rawValue);
  final String rawValue;

  static PetType fromRaw(String value) => PetType.values
      .firstWhere((e) => e.rawValue == value, orElse: () => PetType.cat);
}

/// A care module (category).
///
/// Built-in modules use a stable slug [id] and are localized at display time
/// (their [name] is null); custom modules carry a user-supplied [name] and a
/// generated id so they can be persisted and shared without colliding with the
/// built-in catalog.
class CareCategory {
  const CareCategory.builtIn(this.id) : name = null;

  const CareCategory.custom({required this.id, required this.name});

  final String id;
  final String? name;

  bool get isBuiltIn => name == null;
  String get rawValue => id;

  static const feeding = CareCategory.builtIn('feeding');
  static const walking = CareCategory.builtIn('walking');
  static const medication = CareCategory.builtIn('medication');
  static const grooming = CareCategory.builtIn('grooming');
  static const hospital = CareCategory.builtIn('hospital');
  static const deworming = CareCategory.builtIn('deworming');
  static const nailTrim = CareCategory.builtIn('nailTrim');
  static const peePad = CareCategory.builtIn('peePad');
  static const catLitter = CareCategory.builtIn('catLitter');
  static const water = CareCategory.builtIn('water');
  static const newFood = CareCategory.builtIn('newFood');
  static const dogBath = CareCategory.builtIn('dogBath');
  static const dogTraining = CareCategory.builtIn('dogTraining');
  static const birdCage = CareCategory.builtIn('birdCage');
  static const birdFeather = CareCategory.builtIn('birdFeather');
  static const rabbitHay = CareCategory.builtIn('rabbitHay');
  static const rabbitBedding = CareCategory.builtIn('rabbitBedding');
  static const snakeFeed = CareCategory.builtIn('snakeFeed');
  static const snakeShed = CareCategory.builtIn('snakeShed');
  static const snakeTerrarium = CareCategory.builtIn('snakeTerrarium');
  static const other = CareCategory.builtIn('other');

  static const List<CareCategory> builtIns = [
    feeding,
    walking,
    medication,
    grooming,
    hospital,
    deworming,
    nailTrim,
    peePad,
    catLitter,
    water,
    newFood,
    dogBath,
    dogTraining,
    birdCage,
    birdFeather,
    rabbitHay,
    rabbitBedding,
    snakeFeed,
    snakeShed,
    snakeTerrarium,
    other,
  ];

  static CareCategory fromRaw(String value, {String? name}) {
    for (final category in builtIns) {
      if (category.id == value) return category;
    }
    return CareCategory.custom(id: value, name: name ?? value);
  }

  @override
  bool operator ==(Object other) => other is CareCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum AssignmentMode {
  direct('direct'),
  open('open');

  const AssignmentMode(this.rawValue);
  final String rawValue;

  static AssignmentMode fromRaw(String value) => AssignmentMode.values
      .firstWhere((e) => e.rawValue == value, orElse: () => AssignmentMode.direct);
}

enum CareRoutineFrequency {
  daily('daily'),
  selectedDays('selectedDays'),
  intervalDays('intervalDays'),
  intervalWeeks('intervalWeeks'),
  intervalMonths('intervalMonths'),
  nthWeekday('nthWeekday'),
  intervalYears('intervalYears');

  const CareRoutineFrequency(this.rawValue);
  final String rawValue;

  static CareRoutineFrequency fromRaw(String value) =>
      CareRoutineFrequency.values.firstWhere(
        (e) => e.rawValue == value,
        orElse: () => CareRoutineFrequency.daily,
      );
}

// ---------------------------------------------------------------------------
// Value types
// ---------------------------------------------------------------------------

/// A dated weight measurement for a pet.
class PetWeightEntry {
  const PetWeightEntry({required this.date, required this.weightKg});

  final DateTime date;
  final double weightKg;

  factory PetWeightEntry.fromJson(Map<String, dynamic> json) => PetWeightEntry(
        date: _dateFromJson(json['date']) ?? DateTime.now(),
        weightKg: (json['weightKg'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'date': _dateToJson(date),
        'weightKg': weightKg,
      };
}

/// A single pet belonging to a household.
class Pet {
  const Pet({
    required this.id,
    required this.name,
    this.type = PetType.cat,
    this.ageYears,
    this.habits,
    this.photoURL,
    this.weightKg,
    this.weightHistory = const [],
  });

  final String id;
  final String name;
  final PetType type;
  final int? ageYears;
  final String? habits;
  final String? photoURL;
  final double? weightKg;
  final List<PetWeightEntry> weightHistory;

  Pet copyWith({
    String? name,
    PetType? type,
    int? ageYears,
    String? habits,
    String? photoURL,
    double? weightKg,
    List<PetWeightEntry>? weightHistory,
    bool clearAge = false,
    bool clearHabits = false,
    bool clearPhotoURL = false,
    bool clearWeightKg = false,
  }) {
    return Pet(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      ageYears: clearAge ? null : (ageYears ?? this.ageYears),
      habits: clearHabits ? null : (habits ?? this.habits),
      photoURL: clearPhotoURL ? null : (photoURL ?? this.photoURL),
      weightKg: clearWeightKg ? null : (weightKg ?? this.weightKg),
      weightHistory: weightHistory ?? this.weightHistory,
    );
  }

  factory Pet.fromJson(Map<String, dynamic> json) => Pet(
        id: json['id'] as String,
        name: json['name'] as String,
        type: PetType.fromRaw(json['type'] as String? ?? 'cat'),
        ageYears:
            json['ageYears'] == null ? null : _intFromJson(json['ageYears']),
        habits: _stringFromJson(json['habits']),
        photoURL: _stringFromJson(json['photoURL']),
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        weightHistory: (json['weightHistory'] as List?)
                ?.map((e) => PetWeightEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.rawValue,
        'ageYears': ageYears,
        'habits': habits,
        'photoURL': photoURL,
        'weightKg': weightKg,
        'weightHistory': weightHistory.map((e) => e.toJson()).toList(),
      };
}

class Household {
  const Household({
    required this.id,
    required this.name,
    required this.inviteCode,
    this.pets = const [],
    this.timeZoneIdentifier = '',
  });

  final String id;
  final String name;
  final String inviteCode;
  final List<Pet> pets;
  final String timeZoneIdentifier;

  /// Convenience accessors backed by the first pet (used across the app for
  /// single-pet copy). Prefer iterating [pets] for the full pet list.
  String get petName => pets.isEmpty ? '' : pets.first.name;
  PetType get petType => pets.isEmpty ? PetType.cat : pets.first.type;

  Household copyWith({
    String? name,
    List<Pet>? pets,
    String? inviteCode,
    String? timeZoneIdentifier,
  }) {
    return Household(
      id: id,
      name: name ?? this.name,
      inviteCode: inviteCode ?? this.inviteCode,
      pets: pets ?? this.pets,
      timeZoneIdentifier: timeZoneIdentifier ?? this.timeZoneIdentifier,
    );
  }

  factory Household.fromJson(Map<String, dynamic> json) {
    final petsRaw = json['pets'] as List?;
    return Household(
      id: json['id'] as String,
      name: json['name'] as String,
      inviteCode: json['inviteCode'] as String,
      pets: petsRaw != null
          ? petsRaw
              .map((e) => Pet.fromJson(e as Map<String, dynamic>))
              .toList()
          : _legacyPetsFromJson(json),
      timeZoneIdentifier: _stringFromJson(json['timeZoneIdentifier']) ?? '',
    );
  }

  static List<Pet> _legacyPetsFromJson(Map<String, dynamic> json) {
    final petName = json['petName'] as String?;
    if (petName == null || petName.isEmpty) return const [];
    return [
      Pet(
        id: 'pet-legacy',
        name: petName,
        type: PetType.fromRaw(json['petType'] as String? ?? 'cat'),
      ),
    ];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'inviteCode': inviteCode,
        'pets': pets.map((e) => e.toJson()).toList(),
        'timeZoneIdentifier': timeZoneIdentifier,
      };
}

class Caregiver {
  const Caregiver({required this.id, required this.displayName});

  final String id;
  final String displayName;

  Caregiver copyWith({String? displayName}) =>
      Caregiver(id: id, displayName: displayName ?? this.displayName);

  factory Caregiver.fromJson(Map<String, dynamic> json) => Caregiver(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'displayName': displayName};
}

class AssignmentRequest {
  const AssignmentRequest({
    required this.id,
    required this.requestedByID,
    required this.requestedByNameSnapshot,
    this.requestedToID,
    this.requestedToNameSnapshot,
    this.mode = AssignmentMode.direct,
    required this.createdAt,
  });

  final String id;
  final String requestedByID;
  final String requestedByNameSnapshot;
  final String? requestedToID;
  final String? requestedToNameSnapshot;
  final AssignmentMode mode;
  final DateTime createdAt;

  factory AssignmentRequest.fromJson(Map<String, dynamic> json) =>
      AssignmentRequest(
        id: json['id'] as String,
        requestedByID: json['requestedByID'] as String,
        requestedByNameSnapshot: json['requestedByNameSnapshot'] as String,
        requestedToID: _stringFromJson(json['requestedToID']),
        requestedToNameSnapshot: _stringFromJson(json['requestedToNameSnapshot']),
        mode: AssignmentMode.fromRaw(json['mode'] as String? ?? 'direct'),
        createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'requestedByID': requestedByID,
        'requestedByNameSnapshot': requestedByNameSnapshot,
        'requestedToID': requestedToID,
        'requestedToNameSnapshot': requestedToNameSnapshot,
        'mode': mode.rawValue,
        'createdAt': _dateToJson(createdAt),
      };
}

class CareRoutine {
  const CareRoutine({
    required this.id,
    required this.title,
    required this.category,
    this.priority = CarePriority.normal,
    this.frequency = CareRoutineFrequency.daily,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.interval = 1,
    this.petID,
    required this.hour,
    required this.minute,
    required this.startDate,
    required this.timeZoneIdentifier,
    required this.createdByID,
    required this.createdByNameSnapshot,
    this.isActive = true,
  });

  final String id;
  final String title;
  final CareCategory category;
  final CarePriority priority;
  final CareRoutineFrequency frequency;
  final List<int> weekdays;
  final int interval;
  final String? petID;
  final int hour;
  final int minute;
  final DateTime startDate;
  final String timeZoneIdentifier;
  final String createdByID;
  final String createdByNameSnapshot;
  final bool isActive;

  factory CareRoutine.fromJson(Map<String, dynamic> json) => CareRoutine(
        id: json['id'] as String,
        title: json['title'] as String,
        category: CareCategory.fromRaw(
          json['category'] as String,
          name: _stringFromJson(json['categoryName']),
        ),
        priority: CarePriority.fromRaw(json['priority'] as String? ?? 'normal'),
        frequency:
            CareRoutineFrequency.fromRaw(json['frequency'] as String? ?? 'daily'),
        weekdays: _weekdaysFromJson(json['weekdays']),
        interval: _intFromJson(json['interval'], 1),
        petID: _stringFromJson(json['petID']),
        hour: _intFromJson(json['hour']),
        minute: _intFromJson(json['minute']),
        startDate:
            _dateFromJson(json['startDate']) ?? DateTime.now(),
        timeZoneIdentifier: _stringFromJson(json['timeZoneIdentifier']) ?? '',
        createdByID: json['createdByID'] as String,
        createdByNameSnapshot: json['createdByNameSnapshot'] as String,
        isActive: _boolFromJson(json['isActive'], true),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category.id,
        'categoryName': category.name,
        'priority': priority.rawValue,
        'frequency': frequency.rawValue,
        'weekdays': weekdays,
        'interval': interval,
        'petID': petID,
        'hour': hour,
        'minute': minute,
        'startDate': _dateToJson(startDate),
        'timeZoneIdentifier': timeZoneIdentifier,
        'createdByID': createdByID,
        'createdByNameSnapshot': createdByNameSnapshot,
        'isActive': isActive,
      };
}

class CareTask {
  const CareTask({
    required this.id,
    required this.title,
    required this.category,
    required this.dueTime,
    this.kind = CareTaskKind.oneOff,
    this.priority = CarePriority.normal,
    this.routineID,
    this.petID,
    this.status = CareTaskStatus.unclaimed,
    this.assignmentRequest,
    this.assigneeID,
    this.assigneeNameSnapshot,
    this.claimedAt,
    this.createdByID,
    required this.createdBy,
    DateTime? createdAt,
    this.completedByID,
    this.completedBy,
    this.completedAt,
    this.revision = 0,
  }) : createdAt = createdAt ?? dueTime;

  final String id;
  final String title;
  final CareCategory category;
  final DateTime dueTime;
  final CareTaskKind kind;
  final CarePriority priority;
  final String? routineID;
  final String? petID;
  final CareTaskStatus status;
  final AssignmentRequest? assignmentRequest;
  final String? assigneeID;
  final String? assigneeNameSnapshot;
  final DateTime? claimedAt;
  final String? createdByID;
  final String createdBy;
  final DateTime createdAt;
  final String? completedByID;
  final String? completedBy;
  final DateTime? completedAt;
  final int revision;

  CareTask copyWith({
    CareTaskStatus? status,
    AssignmentRequest? assignmentRequest,
    bool clearAssignmentRequest = false,
    String? assigneeID,
    String? assigneeNameSnapshot,
    DateTime? claimedAt,
    String? completedByID,
    String? completedBy,
    DateTime? completedAt,
    int? revision,
  }) {
    return CareTask(
      id: id,
      title: title,
      category: category,
      dueTime: dueTime,
      kind: kind,
      priority: priority,
      routineID: routineID,
      petID: petID,
      status: status ?? this.status,
      assignmentRequest: clearAssignmentRequest
          ? null
          : (assignmentRequest ?? this.assignmentRequest),
      assigneeID: assigneeID ?? this.assigneeID,
      assigneeNameSnapshot: assigneeNameSnapshot ?? this.assigneeNameSnapshot,
      claimedAt: claimedAt ?? this.claimedAt,
      createdByID: createdByID,
      createdBy: createdBy,
      createdAt: createdAt,
      completedByID: completedByID ?? this.completedByID,
      completedBy: completedBy ?? this.completedBy,
      completedAt: completedAt ?? this.completedAt,
      revision: revision ?? this.revision,
    );
  }

  factory CareTask.fromJson(Map<String, dynamic> json) => CareTask(
        id: json['id'] as String,
        title: json['title'] as String,
        category: CareCategory.fromRaw(
          json['category'] as String,
          name: _stringFromJson(json['categoryName']),
        ),
        dueTime: _dateFromJson(json['dueTime']) ?? DateTime.now(),
        kind: CareTaskKind.fromRaw(json['kind'] as String? ?? 'oneOff'),
        priority: CarePriority.fromRaw(json['priority'] as String? ?? 'normal'),
        routineID: _stringFromJson(json['routineID']),
        petID: _stringFromJson(json['petID']),
        status: CareTaskStatus.fromRaw(json['status'] as String? ?? 'unclaimed'),
        assignmentRequest: json['assignmentRequest'] == null
            ? null
            : AssignmentRequest.fromJson(
                json['assignmentRequest'] as Map<String, dynamic>),
        assigneeID: _stringFromJson(json['assigneeID']),
        assigneeNameSnapshot: _stringFromJson(json['assigneeNameSnapshot']),
        claimedAt: _dateFromJson(json['claimedAt']),
        createdByID: _stringFromJson(json['createdByID']),
        createdBy: json['createdBy'] as String,
        createdAt: _dateFromJson(json['createdAt']),
        completedByID: _stringFromJson(json['completedByID']),
        completedBy: _stringFromJson(json['completedBy']),
        completedAt: _dateFromJson(json['completedAt']),
        revision: _intFromJson(json['revision']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category.id,
        'categoryName': category.name,
        'dueTime': _dateToJson(dueTime),
        'kind': kind.rawValue,
        'priority': priority.rawValue,
        'routineID': routineID,
        'petID': petID,
        'status': status.rawValue,
        'assignmentRequest': assignmentRequest?.toJson(),
        'assigneeID': assigneeID,
        'assigneeNameSnapshot': assigneeNameSnapshot,
        'claimedAt': _dateToJson(claimedAt),
        'createdByID': createdByID,
        'createdBy': createdBy,
        'createdAt': _dateToJson(createdAt),
        'completedByID': completedByID,
        'completedBy': completedBy,
        'completedAt': _dateToJson(completedAt),
        'revision': revision,
      };
}

class CareSession {
  const CareSession({required this.household, required this.caregiver});

  final Household household;
  final Caregiver caregiver;
}
