/// Core domain models for pettogether.
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

List<String> _stringListFromJson(dynamic value) {
  if (value is List) return value.whereType<String>().toList();
  return const [];
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum CareTaskStatus {
  unclaimed('unclaimed'),
  claimed('claimed'),
  completed('completed'),
  skipped('skipped');

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
      case 'skipped':
        return CareTaskStatus.skipped;
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
  snake('snake'),
  fish('fish'),
  hamster('hamster'),
  guineaPig('guineaPig'),
  ferret('ferret'),
  turtle('turtle'),
  reptile('reptile'),
  amphibian('amphibian'),
  horse('horse'),
  other('other');

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

/// Why a scheduled dose was not given.
///
/// Lives here rather than with the medication models because it is stored on
/// [CareTask] — a medication dose *is* a care task, and skipping one is only
/// meaningful with a reason attached ("refused it twice, vomited once" is a
/// finding a vet can use).
enum MedicationSkipReason {
  petRefused('petRefused'),
  vomited('vomited'),
  outOfStock('outOfStock'),
  vetInstruction('vetInstruction'),
  alreadyGiven('alreadyGiven'),
  other('other');

  const MedicationSkipReason(this.rawValue);
  final String rawValue;

  static MedicationSkipReason fromRaw(String value) =>
      MedicationSkipReason.values.firstWhere(
        (e) => e.rawValue == value,
        orElse: () => MedicationSkipReason.other,
      );

  /// `other` says nothing on its own, so the UI requires a note with it.
  bool get requiresNote => this == MedicationSkipReason.other;
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
    this.ownerID,
  });

  final String id;
  final String name;
  final String inviteCode;
  final List<Pet> pets;
  final String timeZoneIdentifier;

  /// The Firestore user id of the household owner. Null on legacy documents
  /// created before this field existed (falls back to the sole member).
  final String? ownerID;

  /// Convenience accessors backed by the first pet (used across the app for
  /// single-pet copy). Prefer iterating [pets] for the full pet list.
  String get petName => pets.isEmpty ? '' : pets.first.name;
  PetType get petType => pets.isEmpty ? PetType.cat : pets.first.type;

  Household copyWith({
    String? name,
    List<Pet>? pets,
    String? inviteCode,
    String? timeZoneIdentifier,
    String? ownerID,
  }) {
    return Household(
      id: id,
      name: name ?? this.name,
      inviteCode: inviteCode ?? this.inviteCode,
      pets: pets ?? this.pets,
      timeZoneIdentifier: timeZoneIdentifier ?? this.timeZoneIdentifier,
      ownerID: ownerID ?? this.ownerID,
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
      ownerID: _stringFromJson(json['ownerID']),
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
        'ownerID': ownerID,
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
    this.petIds = const [],
    required this.hour,
    required this.minute,
    required this.startDate,
    this.endDate,
    required this.timeZoneIdentifier,
    required this.createdByID,
    required this.createdByNameSnapshot,
    this.isActive = true,
    this.medicationPlanId,
    this.doseText,
    this.doseInstructions,
  });

  final String id;
  final String title;
  final CareCategory category;
  final CarePriority priority;
  final CareRoutineFrequency frequency;
  final List<int> weekdays;
  final int interval;

  /// Legacy single-pet pointer; kept for backward compatibility.
  final String? petID;

  /// Pets this routine applies to. Empty means every household pet (legacy).
  final List<String> petIds;

  /// Pets this routine applies to, honouring the legacy [petID] fallback.
  List<String> get effectivePetIds =>
      petIds.isNotEmpty ? petIds : (petID == null ? const [] : [petID!]);

  final int hour;
  final int minute;
  final DateTime startDate;

  /// Last day this routine runs, inclusive. Null means it runs indefinitely.
  ///
  /// Medication courses always set it ("seven days from Tuesday"), but it is
  /// just as useful for an ordinary routine that ends — extra walks while a
  /// leg heals, say.
  final DateTime? endDate;

  final String timeZoneIdentifier;
  final String createdByID;
  final String createdByNameSnapshot;
  final bool isActive;

  /// Links this dose time back to its [MedicationPlan] when the routine is
  /// part of a medication course. Null for ordinary care routines.
  ///
  /// A course with two doses a day is two routines sharing one plan id; the
  /// plan holds only the drug details, the routines hold the schedule.
  final String? medicationPlanId;

  /// How much to give at this time: "half a tablet", "0.5 ml".
  final String? doseText;

  /// How to give it: "after food", "hide it in a treat".
  final String? doseInstructions;

  bool get isMedication => medicationPlanId != null;

  CareRoutine copyWith({
    String? title,
    CareCategory? category,
    CarePriority? priority,
    CareRoutineFrequency? frequency,
    List<int>? weekdays,
    int? interval,
    String? petID,
    List<String>? petIds,
    int? hour,
    int? minute,
    DateTime? startDate,
    DateTime? endDate,
    String? timeZoneIdentifier,
    bool? isActive,
    String? medicationPlanId,
    String? doseText,
    String? doseInstructions,
    bool clearEndDate = false,
    bool clearDoseInstructions = false,
  }) {
    return CareRoutine(
      id: id,
      title: title ?? this.title,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      frequency: frequency ?? this.frequency,
      weekdays: weekdays ?? this.weekdays,
      interval: interval ?? this.interval,
      petID: petID ?? this.petID,
      petIds: petIds ?? this.petIds,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      timeZoneIdentifier: timeZoneIdentifier ?? this.timeZoneIdentifier,
      createdByID: createdByID,
      createdByNameSnapshot: createdByNameSnapshot,
      isActive: isActive ?? this.isActive,
      medicationPlanId: medicationPlanId ?? this.medicationPlanId,
      doseText: doseText ?? this.doseText,
      doseInstructions: clearDoseInstructions
          ? null
          : (doseInstructions ?? this.doseInstructions),
    );
  }

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
        petIds: _stringListFromJson(json['petIds']),
        hour: _intFromJson(json['hour']),
        minute: _intFromJson(json['minute']),
        startDate:
            _dateFromJson(json['startDate']) ?? DateTime.now(),
        endDate: _dateFromJson(json['endDate']),
        timeZoneIdentifier: _stringFromJson(json['timeZoneIdentifier']) ?? '',
        createdByID: json['createdByID'] as String,
        createdByNameSnapshot: json['createdByNameSnapshot'] as String,
        isActive: _boolFromJson(json['isActive'], true),
        medicationPlanId: _stringFromJson(json['medicationPlanId']),
        doseText: _stringFromJson(json['doseText']),
        doseInstructions: _stringFromJson(json['doseInstructions']),
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
        'petIds': petIds,
        'hour': hour,
        'minute': minute,
        'startDate': _dateToJson(startDate),
        'endDate': _dateToJson(endDate),
        'timeZoneIdentifier': timeZoneIdentifier,
        'createdByID': createdByID,
        'createdByNameSnapshot': createdByNameSnapshot,
        'isActive': isActive,
        'medicationPlanId': medicationPlanId,
        'doseText': doseText,
        'doseInstructions': doseInstructions,
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
    this.petIds = const [],
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
    this.skipReason,
    this.skipNote,
    this.isServerConfirmed = true,
  }) : createdAt = createdAt ?? dueTime;

  final String id;
  final String title;
  final CareCategory category;
  final DateTime dueTime;
  final CareTaskKind kind;
  final CarePriority priority;
  final String? routineID;

  /// Legacy single-pet pointer; kept for backward compatibility.
  final String? petID;

  /// Pets this task applies to. Empty means every household pet (legacy).
  final List<String> petIds;

  /// Pets this task applies to, honouring the legacy [petID] fallback.
  List<String> get effectivePetIds =>
      petIds.isNotEmpty ? petIds : (petID == null ? const [] : [petID!]);

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

  /// Why a medication dose was skipped. Ordinary tasks leave this null — "no
  /// walk today" needs no explanation, a missed dose does.
  final MedicationSkipReason? skipReason;

  /// Free-text detail for the skip; required when [skipReason] is `other`.
  final String? skipNote;

  /// False while this task is only in the local cache or has a pending write.
  /// Not persisted — it describes the snapshot, not the task.
  ///
  /// Medication cards refuse to show an unconfirmed completion as done:
  /// believing a dose was already given is the one failure here that could
  /// leave an animal dosed twice, or not at all.
  final bool isServerConfirmed;

  static const int maxSkipNoteLength = 200;

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
    MedicationSkipReason? skipReason,
    String? skipNote,
    bool? isServerConfirmed,
    bool clearSkipReason = false,
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
      petIds: petIds,
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
      skipReason: clearSkipReason ? null : (skipReason ?? this.skipReason),
      skipNote: clearSkipReason ? null : (skipNote ?? this.skipNote),
      isServerConfirmed: isServerConfirmed ?? this.isServerConfirmed,
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
        petIds: _stringListFromJson(json['petIds']),
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
        skipReason: json['skipReason'] == null
            ? null
            : MedicationSkipReason.fromRaw(json['skipReason'] as String),
        skipNote: _stringFromJson(json['skipNote']),
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
        'petIds': petIds,
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
        'skipReason': skipReason?.rawValue,
        'skipNote': skipNote,
      };
}

class CareSession {
  const CareSession({required this.household, required this.caregiver});

  final Household household;
  final Caregiver caregiver;
}

// ---------------------------------------------------------------------------
// Invitations & join requests (Kate flow: link/QR + owner approval)
// ---------------------------------------------------------------------------

enum InvitationStatus {
  active('active'),
  claimed('claimed'),
  approved('approved'),
  rejected('rejected'),
  revoked('revoked');

  const InvitationStatus(this.rawValue);
  final String rawValue;

  static InvitationStatus fromRaw(String value) => InvitationStatus.values
      .firstWhere((e) => e.rawValue == value, orElse: () => InvitationStatus.active);
}

enum JoinRequestStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const JoinRequestStatus(this.rawValue);
  final String rawValue;

  static JoinRequestStatus fromRaw(String value) => JoinRequestStatus.values
      .firstWhere((e) => e.rawValue == value, orElse: () => JoinRequestStatus.pending);
}

/// A one-time, expiring invitation to a household. The deep link
/// `pettogether://invite/<id>` (also encoded as a QR code) carries the id.
class HouseholdInvitation {
  const HouseholdInvitation({
    required this.id,
    required this.householdId,
    required this.householdName,
    required this.petNames,
    required this.inviterName,
    required this.invitedBy,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.claimedBy,
    this.claimedName,
    this.claimedAt,
    this.reviewedBy,
    this.reviewedAt,
  });

  final String id;
  final String householdId;
  final String householdName;
  final List<String> petNames;
  final String inviterName;
  final String invitedBy;
  final InvitationStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? claimedBy;
  final String? claimedName;
  final DateTime? claimedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;

  String get deepLink => 'pettogether://invite/$id';

  bool get isActive =>
      status == InvitationStatus.active && expiresAt.isAfter(DateTime.now());

  factory HouseholdInvitation.fromJson(Map<String, dynamic> json) =>
      HouseholdInvitation(
        id: json['id'] as String,
        householdId: json['householdId'] as String,
        householdName: json['householdName'] as String,
        petNames: _stringListFromJson(json['petNames']),
        inviterName: json['inviterName'] as String,
        invitedBy: json['invitedBy'] as String,
        status: InvitationStatus.fromRaw(json['status'] as String? ?? 'active'),
        createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now(),
        expiresAt: _dateFromJson(json['expiresAt']) ??
            DateTime.now().add(const Duration(days: 1)),
        claimedBy: _stringFromJson(json['claimedBy']),
        claimedName: _stringFromJson(json['claimedName']),
        claimedAt: _dateFromJson(json['claimedAt']),
        reviewedBy: _stringFromJson(json['reviewedBy']),
        reviewedAt: _dateFromJson(json['reviewedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'householdId': householdId,
        'householdName': householdName,
        'petNames': petNames,
        'inviterName': inviterName,
        'invitedBy': invitedBy,
        'status': status.rawValue,
        'createdAt': _dateToJson(createdAt),
        'expiresAt': _dateToJson(expiresAt),
        'claimedBy': claimedBy,
        'claimedName': claimedName,
        'claimedAt': _dateToJson(claimedAt),
        'reviewedBy': reviewedBy,
        'reviewedAt': _dateToJson(reviewedAt),
      };
}

/// A pending/approved/rejected request to join a household, created when a
/// joiner claims an invitation link/QR code.
class HouseholdJoinRequest {
  const HouseholdJoinRequest({
    required this.userId,
    required this.householdId,
    required this.invitationId,
    required this.name,
    required this.status,
    required this.createdAt,
    this.email,
    this.reviewedBy,
    this.reviewedAt,
  });

  final String userId;
  final String householdId;
  final String invitationId;
  final String name;
  final String? email;
  final JoinRequestStatus status;
  final DateTime createdAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;

  bool get isPending => status == JoinRequestStatus.pending;

  factory HouseholdJoinRequest.fromJson(Map<String, dynamic> json) =>
      HouseholdJoinRequest(
        userId: json['userId'] as String,
        householdId: json['householdId'] as String,
        invitationId: json['invitationId'] as String,
        name: json['name'] as String,
        email: _stringFromJson(json['email']),
        status: JoinRequestStatus.fromRaw(json['status'] as String? ?? 'pending'),
        createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now(),
        reviewedBy: _stringFromJson(json['reviewedBy']),
        reviewedAt: _dateFromJson(json['reviewedAt']),
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'householdId': householdId,
        'invitationId': invitationId,
        'name': name,
        'email': email,
        'status': status.rawValue,
        'createdAt': _dateToJson(createdAt),
        'reviewedBy': reviewedBy,
        'reviewedAt': _dateToJson(reviewedAt),
      };
}
