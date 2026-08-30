/// Health-record domain models for pettogether: what a medicine is, and the medical
/// history (vet visits, vaccinations, lab results…).
///
/// Individual doses are deliberately *not* here. A dose is a [CareTask]
/// expanded from a [CareRoutine] — see `CareStore.doseTasksOn` — so it inherits
/// claiming, assignment and completion from the ordinary care flow instead of
/// running a parallel one.
///
/// These follow the same conventions as `models.dart`: string-valued enums
/// with a `rawValue` and a defaulting `fromRaw`, dates serialized as epoch
/// milliseconds in JSON (Firestore `Timestamp`s are converted in the service
/// layer), and `toJson()` writing every key including nulls.
library;

// ---------------------------------------------------------------------------
// Small helpers (mirrors the private helpers in models.dart)
// ---------------------------------------------------------------------------

DateTime? _dateFromJson(dynamic value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) {
    final ms = int.tryParse(value);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
  return null;
}

int? _dateToJson(DateTime? value) => value?.millisecondsSinceEpoch;

String? _stringFromJson(dynamic value) => value is String ? value : null;

int _intFromJson(dynamic value, [int fallback = 0]) =>
    value is int ? value : (value is num ? value.toInt() : fallback);

int? _nullableIntFromJson(dynamic value) =>
    value is num ? value.toInt() : null;

double? _doubleFromJson(dynamic value) =>
    value is num ? value.toDouble() : null;

bool _boolFromJson(dynamic value, [bool fallback = false]) =>
    value is bool ? value : fallback;

/// Local midnight, used so course start/end dates compare by day.
DateTime _dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);

// ---------------------------------------------------------------------------
// Medication
// ---------------------------------------------------------------------------

/// How a medicine is given. Purely descriptive — it drives the icon and helps
/// a caregiver who has never given this medicine before.
enum MedicationForm {
  oral('oral'),
  topical('topical'),
  injection('injection'),
  eyeDrop('eyeDrop'),
  earDrop('earDrop'),
  inhaler('inhaler'),
  powder('powder'),
  other('other');

  const MedicationForm(this.rawValue);
  final String rawValue;

  static MedicationForm fromRaw(String value) => MedicationForm.values
      .firstWhere((e) => e.rawValue == value, orElse: () => MedicationForm.oral);
}

/// One dose time in a medication course: when to give it and how much.
///
/// This is the *input* shape for building a course. Once saved, each dose time
/// becomes a [CareRoutine] — the routines own the schedule, the plan owns only
/// the drug details, so the two can never drift apart.
class MedicationDoseTime {
  const MedicationDoseTime({
    required this.hour,
    required this.minute,
    required this.doseText,
    this.instructions,
  });

  final int hour;
  final int minute;

  /// "Half a tablet", "0.5 ml".
  final String doseText;

  /// "After food", "hide it in a treat".
  final String? instructions;

  static const int maxDoseTextLength = 80;
  static const int maxInstructionsLength = 500;

  int get minutesOfDay => hour * 60 + minute;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  bool get isValid =>
      hour >= 0 &&
      hour <= 23 &&
      minute >= 0 &&
      minute <= 59 &&
      doseText.trim().isNotEmpty &&
      doseText.length <= maxDoseTextLength &&
      (instructions == null || instructions!.length <= maxInstructionsLength);

  MedicationDoseTime copyWith({
    int? hour,
    int? minute,
    String? doseText,
    String? instructions,
    bool clearInstructions = false,
  }) {
    return MedicationDoseTime(
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      doseText: doseText ?? this.doseText,
      instructions:
          clearInstructions ? null : (instructions ?? this.instructions),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MedicationDoseTime &&
      other.hour == hour &&
      other.minute == minute &&
      other.doseText == doseText &&
      other.instructions == instructions;

  @override
  int get hashCode => Object.hash(hour, minute, doseText, instructions);
}

/// What a medicine is and why the pet is on it.
///
/// Deliberately holds no schedule. A course's dose times, weekdays and start /
/// end dates live on its [CareRoutine]s, which is what makes a dose an
/// ordinary care task — claimable, assignable, completable — rather than a
/// parallel kind of thing.
class MedicationPlan {
  const MedicationPlan({
    required this.id,
    required this.petId,
    required this.name,
    this.form = MedicationForm.oral,
    this.purpose,
    this.sideEffects,
    this.isActive = true,
    this.remainingDoses,
    required this.createdByID,
    required this.createdByNameSnapshot,
    required this.createdAt,
    this.revision = 0,
  });

  final String id;
  final String petId;

  /// The medicine's name, as written on the box.
  final String name;
  final MedicationForm form;

  /// What it is being given for. Three months later nobody remembers.
  final String? purpose;

  /// Side effects to watch for, so a caregiver who never spoke to the vet
  /// still knows what "not normal" looks like.
  final String? sideEffects;

  /// False once the course has been stopped. Stopped courses keep their
  /// documents so history and adherence stay readable.
  final bool isActive;

  /// Optional count of doses left in the box, for a "running low" nudge.
  final int? remainingDoses;

  final String createdByID;
  final String createdByNameSnapshot;
  final DateTime createdAt;
  final int revision;

  static const int maxNameLength = 120;
  static const int maxPurposeLength = 500;
  static const int maxSideEffectsLength = 500;

  /// A course may have at most this many dose times a day.
  static const int maxDoseTimes = 8;

  /// True once the medicine is nearly gone, if the owner tracked the count.
  bool get isRunningLow =>
      remainingDoses != null && remainingDoses! > 0 && remainingDoses! <= 3;

  bool get isValid =>
      petId.isNotEmpty &&
      name.trim().isNotEmpty &&
      name.length <= maxNameLength &&
      (purpose == null || purpose!.length <= maxPurposeLength) &&
      (sideEffects == null || sideEffects!.length <= maxSideEffectsLength);

  MedicationPlan copyWith({
    String? name,
    MedicationForm? form,
    String? purpose,
    String? sideEffects,
    bool? isActive,
    int? remainingDoses,
    int? revision,
    bool clearPurpose = false,
    bool clearSideEffects = false,
    bool clearRemainingDoses = false,
  }) {
    return MedicationPlan(
      id: id,
      petId: petId,
      name: name ?? this.name,
      form: form ?? this.form,
      purpose: clearPurpose ? null : (purpose ?? this.purpose),
      sideEffects: clearSideEffects ? null : (sideEffects ?? this.sideEffects),
      isActive: isActive ?? this.isActive,
      remainingDoses:
          clearRemainingDoses ? null : (remainingDoses ?? this.remainingDoses),
      createdByID: createdByID,
      createdByNameSnapshot: createdByNameSnapshot,
      createdAt: createdAt,
      revision: revision ?? this.revision,
    );
  }

  factory MedicationPlan.fromJson(Map<String, dynamic> json) => MedicationPlan(
        id: json['id'] as String,
        petId: _stringFromJson(json['petId']) ?? '',
        name: _stringFromJson(json['name']) ?? '',
        form: MedicationForm.fromRaw(json['form'] as String? ?? 'oral'),
        purpose: _stringFromJson(json['purpose']),
        sideEffects: _stringFromJson(json['sideEffects']),
        isActive: _boolFromJson(json['isActive'], true),
        remainingDoses: _nullableIntFromJson(json['remainingDoses']),
        createdByID: _stringFromJson(json['createdByID']) ?? '',
        createdByNameSnapshot:
            _stringFromJson(json['createdByNameSnapshot']) ?? '',
        createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now(),
        revision: _intFromJson(json['revision']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'petId': petId,
        'name': name,
        'form': form.rawValue,
        'purpose': purpose,
        'sideEffects': sideEffects,
        'isActive': isActive,
        'remainingDoses': remainingDoses,
        'createdByID': createdByID,
        'createdByNameSnapshot': createdByNameSnapshot,
        'createdAt': _dateToJson(createdAt),
        'revision': revision,
      };
}

/// How much of a course actually happened over a window.
///
/// [missed] counts doses whose time passed with nobody recording anything —
/// they are part of the picture a vet needs, so they are never dropped from
/// the denominator.
class MedicationAdherence {
  const MedicationAdherence({
    required this.given,
    required this.skipped,
    required this.missed,
  });

  final int given;
  final int skipped;
  final int missed;

  int get planned => given + skipped + missed;

  /// Null rather than 0 when nothing was scheduled — "no data" and "took
  /// nothing" must not look the same.
  double? get rate => planned == 0 ? null : given / planned;

  int? get percent {
    final value = rate;
    return value == null ? null : (value * 100).round();
  }

  bool get isEmpty => planned == 0;
}

// ---------------------------------------------------------------------------
// Medical history
// ---------------------------------------------------------------------------

/// The kind of medical event a [HealthRecord] captures. The record editor
/// shows a different set of fields per type, so a vet visit is not stored as
/// one undifferentiated blob of text.
enum HealthRecordType {
  vetVisit('vetVisit'),
  vaccination('vaccination'),
  deworming('deworming'),
  labResult('labResult'),
  surgery('surgery'),
  symptom('symptom'),
  weight('weight'),
  medication('medication'),
  note('note');

  const HealthRecordType(this.rawValue);
  final String rawValue;

  static HealthRecordType fromRaw(String value) => HealthRecordType.values
      .firstWhere((e) => e.rawValue == value, orElse: () => HealthRecordType.note);

  /// Types that happen at a clinic and carry a diagnosis / treatment.
  bool get hasClinicDetails =>
      this == HealthRecordType.vetVisit ||
      this == HealthRecordType.surgery ||
      this == HealthRecordType.labResult;

  /// Written automatically when a medication course is created, so a course
  /// shows up in the history next to the visit that prescribed it. Not offered
  /// in the record editor's type picker — it is owned by the course.
  bool get isCourseGenerated => this == HealthRecordType.medication;

  /// Types that recur on a schedule and therefore deserve a "next due" date.
  bool get hasNextDue =>
      this == HealthRecordType.vaccination || this == HealthRecordType.deworming;

  bool get hasDiagnosis =>
      this == HealthRecordType.vetVisit || this == HealthRecordType.surgery;

  bool get hasCost =>
      this == HealthRecordType.vetVisit ||
      this == HealthRecordType.surgery ||
      this == HealthRecordType.labResult;
}

/// A photo attached to a health record: a lab printout, a prescription, a
/// picture of the affected paw.
class HealthAttachment {
  const HealthAttachment({
    required this.id,
    required this.url,
    required this.storagePath,
    this.caption,
    this.sizeBytes,
    required this.uploadedAt,
  });

  final String id;
  final String url;

  /// The Storage object path, kept so the file can be deleted with the record.
  final String storagePath;
  final String? caption;
  final int? sizeBytes;
  final DateTime uploadedAt;

  /// Uploads above this are rejected client-side; a phone photo compressed to
  /// 1600px stays well under it.
  static const int maxBytes = 5 * 1024 * 1024;

  factory HealthAttachment.fromJson(Map<String, dynamic> json) =>
      HealthAttachment(
        id: json['id'] as String,
        url: _stringFromJson(json['url']) ?? '',
        storagePath: _stringFromJson(json['storagePath']) ?? '',
        caption: _stringFromJson(json['caption']),
        sizeBytes: _nullableIntFromJson(json['sizeBytes']),
        uploadedAt: _dateFromJson(json['uploadedAt']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'storagePath': storagePath,
        'caption': caption,
        'sizeBytes': sizeBytes,
        'uploadedAt': _dateToJson(uploadedAt),
      };
}

/// One entry in a pet's medical history.
///
/// Unlike a care task, a health record describes something that already
/// happened, so [occurredAt] is chosen by the person writing it and can be
/// backdated — you rarely open the app while the vet is still talking.
class HealthRecord {
  const HealthRecord({
    required this.id,
    required this.petId,
    required this.petNameSnapshot,
    required this.type,
    required this.occurredAt,
    required this.title,
    this.clinicName,
    this.vetName,
    this.diagnosis,
    this.treatment,
    this.costMinor,
    this.currency,
    this.productName,
    this.lotNumber,
    this.nextDueAt,
    this.weightKg,
    this.temperatureC,
    this.notes,
    this.attachments = const [],
    this.medicationPlanId,
    required this.createdByID,
    required this.createdByNameSnapshot,
    required this.createdAt,
    this.updatedAt,
    this.updatedByID,
    this.updatedByNameSnapshot,
    this.revision = 0,
  });

  final String id;
  final String petId;
  final String petNameSnapshot;
  final HealthRecordType type;

  /// When the event happened — not when it was typed in.
  final DateTime occurredAt;

  /// A one-line summary; this is what the timeline and the PDF show.
  final String title;

  // Clinic types
  final String? clinicName;
  final String? vetName;
  final String? diagnosis;
  final String? treatment;

  /// Cost in the currency's minor unit (yen has none, so it is just yen).
  final int? costMinor;
  final String? currency;

  // Vaccination / deworming
  final String? productName;
  final String? lotNumber;

  /// When the next shot / dose is due. This is what turns a vaccination record
  /// into a reminder instead of a dead entry.
  final DateTime? nextDueAt;

  // Measurements
  final double? weightKg;
  final double? temperatureC;

  final String? notes;
  final List<HealthAttachment> attachments;

  /// Set on the entry a medication course writes for itself, so the course can
  /// find and update its own history line instead of leaving duplicates.
  final String? medicationPlanId;

  final String createdByID;
  final String createdByNameSnapshot;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? updatedByID;
  final String? updatedByNameSnapshot;
  final int revision;

  static const int maxTitleLength = 120;
  static const int maxNotesLength = 2000;
  static const int maxFieldLength = 200;
  static const int maxAttachments = 10;

  bool get wasEdited => updatedAt != null;

  bool get isValid =>
      petId.isNotEmpty &&
      title.trim().isNotEmpty &&
      title.length <= maxTitleLength &&
      (notes == null || notes!.length <= maxNotesLength) &&
      attachments.length <= maxAttachments &&
      (type != HealthRecordType.weight || weightKg != null);

  /// Days until [nextDueAt], negative once overdue. Null when not scheduled.
  int? daysUntilDue([DateTime? now]) {
    final due = nextDueAt;
    if (due == null) return null;
    final today = _dayOnly(now ?? DateTime.now());
    return _dayOnly(due).difference(today).inDays;
  }

  HealthRecord copyWith({
    HealthRecordType? type,
    DateTime? occurredAt,
    String? title,
    String? clinicName,
    String? vetName,
    String? diagnosis,
    String? treatment,
    int? costMinor,
    String? currency,
    String? productName,
    String? lotNumber,
    DateTime? nextDueAt,
    double? weightKg,
    double? temperatureC,
    String? notes,
    List<HealthAttachment>? attachments,
    String? medicationPlanId,
    DateTime? updatedAt,
    String? updatedByID,
    String? updatedByNameSnapshot,
    int? revision,
    bool clearClinicName = false,
    bool clearVetName = false,
    bool clearDiagnosis = false,
    bool clearTreatment = false,
    bool clearCost = false,
    bool clearProductName = false,
    bool clearLotNumber = false,
    bool clearNextDueAt = false,
    bool clearWeightKg = false,
    bool clearTemperatureC = false,
    bool clearNotes = false,
  }) {
    return HealthRecord(
      id: id,
      petId: petId,
      petNameSnapshot: petNameSnapshot,
      type: type ?? this.type,
      occurredAt: occurredAt ?? this.occurredAt,
      title: title ?? this.title,
      clinicName: clearClinicName ? null : (clinicName ?? this.clinicName),
      vetName: clearVetName ? null : (vetName ?? this.vetName),
      diagnosis: clearDiagnosis ? null : (diagnosis ?? this.diagnosis),
      treatment: clearTreatment ? null : (treatment ?? this.treatment),
      costMinor: clearCost ? null : (costMinor ?? this.costMinor),
      currency: clearCost ? null : (currency ?? this.currency),
      productName: clearProductName ? null : (productName ?? this.productName),
      lotNumber: clearLotNumber ? null : (lotNumber ?? this.lotNumber),
      nextDueAt: clearNextDueAt ? null : (nextDueAt ?? this.nextDueAt),
      weightKg: clearWeightKg ? null : (weightKg ?? this.weightKg),
      temperatureC:
          clearTemperatureC ? null : (temperatureC ?? this.temperatureC),
      notes: clearNotes ? null : (notes ?? this.notes),
      attachments: attachments ?? this.attachments,
      medicationPlanId: medicationPlanId ?? this.medicationPlanId,
      createdByID: createdByID,
      createdByNameSnapshot: createdByNameSnapshot,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByID: updatedByID ?? this.updatedByID,
      updatedByNameSnapshot:
          updatedByNameSnapshot ?? this.updatedByNameSnapshot,
      revision: revision ?? this.revision,
    );
  }

  factory HealthRecord.fromJson(Map<String, dynamic> json) => HealthRecord(
        id: json['id'] as String,
        petId: _stringFromJson(json['petId']) ?? '',
        petNameSnapshot: _stringFromJson(json['petNameSnapshot']) ?? '',
        type: HealthRecordType.fromRaw(json['type'] as String? ?? 'note'),
        occurredAt: _dateFromJson(json['occurredAt']) ?? DateTime.now(),
        title: _stringFromJson(json['title']) ?? '',
        clinicName: _stringFromJson(json['clinicName']),
        vetName: _stringFromJson(json['vetName']),
        diagnosis: _stringFromJson(json['diagnosis']),
        treatment: _stringFromJson(json['treatment']),
        costMinor: _nullableIntFromJson(json['costMinor']),
        currency: _stringFromJson(json['currency']),
        productName: _stringFromJson(json['productName']),
        lotNumber: _stringFromJson(json['lotNumber']),
        nextDueAt: _dateFromJson(json['nextDueAt']),
        weightKg: _doubleFromJson(json['weightKg']),
        temperatureC: _doubleFromJson(json['temperatureC']),
        notes: _stringFromJson(json['notes']),
        attachments: (json['attachments'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    HealthAttachment.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
        medicationPlanId: _stringFromJson(json['medicationPlanId']),
        createdByID: _stringFromJson(json['createdByID']) ?? '',
        createdByNameSnapshot:
            _stringFromJson(json['createdByNameSnapshot']) ?? '',
        createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now(),
        updatedAt: _dateFromJson(json['updatedAt']),
        updatedByID: _stringFromJson(json['updatedByID']),
        updatedByNameSnapshot: _stringFromJson(json['updatedByNameSnapshot']),
        revision: _intFromJson(json['revision']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'petId': petId,
        'petNameSnapshot': petNameSnapshot,
        'type': type.rawValue,
        'occurredAt': _dateToJson(occurredAt),
        'title': title,
        'clinicName': clinicName,
        'vetName': vetName,
        'diagnosis': diagnosis,
        'treatment': treatment,
        'costMinor': costMinor,
        'currency': currency,
        'productName': productName,
        'lotNumber': lotNumber,
        'nextDueAt': _dateToJson(nextDueAt),
        'weightKg': weightKg,
        'temperatureC': temperatureC,
        'notes': notes,
        'attachments': attachments.map((e) => e.toJson()).toList(),
        'medicationPlanId': medicationPlanId,
        'createdByID': createdByID,
        'createdByNameSnapshot': createdByNameSnapshot,
        'createdAt': _dateToJson(createdAt),
        'updatedAt': _dateToJson(updatedAt),
        'updatedByID': updatedByID,
        'updatedByNameSnapshot': updatedByNameSnapshot,
        'revision': revision,
      };
}

/// A vaccination or deworming record whose next dose is coming up, surfaced on
/// the pet's health summary and pushed as a reminder.
class HealthDueReminder {
  const HealthDueReminder({
    required this.record,
    required this.daysUntilDue,
  });

  final HealthRecord record;
  final int daysUntilDue;

  bool get isOverdue => daysUntilDue < 0;
  bool get isDueToday => daysUntilDue == 0;

  /// How far ahead the summary card and reminders look.
  static const int lookAheadDays = 14;
}
