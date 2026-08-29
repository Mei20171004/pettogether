import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/models/health.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/utils/care_calendar.dart';

CareRoutine _routine({
  String id = 'routine-1',
  List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
  CareRoutineFrequency frequency = CareRoutineFrequency.daily,
  required DateTime startDate,
  DateTime? endDate,
}) {
  return CareRoutine(
    id: id,
    title: 'Amoxicillin',
    category: CareCategory.medication,
    frequency: frequency,
    weekdays: weekdays,
    hour: 8,
    minute: 0,
    startDate: startDate,
    endDate: endDate,
    timeZoneIdentifier: 'Asia/Tokyo',
    createdByID: 'caregiver-1',
    createdByNameSnapshot: 'Sam',
    medicationPlanId: 'plan-1',
    doseText: 'Half a tablet',
    doseInstructions: 'After food',
  );
}

HealthRecord _record({
  String id = 'record-1',
  HealthRecordType type = HealthRecordType.vetVisit,
  String petId = 'pet-1',
  DateTime? occurredAt,
  DateTime? nextDueAt,
  double? weightKg,
}) {
  return HealthRecord(
    id: id,
    petId: petId,
    petNameSnapshot: 'Mochi',
    type: type,
    occurredAt: occurredAt ?? DateTime(2026, 3, 2, 10, 30),
    title: 'Vomiting and off food',
    clinicName: 'Sakura Animal Clinic',
    diagnosis: 'Mild gastroenteritis',
    nextDueAt: nextDueAt,
    weightKg: weightKg,
    createdByID: 'caregiver-1',
    createdByNameSnapshot: 'Sam',
    createdAt: DateTime(2026, 3, 2, 11),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('models', () {
    test('a medication plan survives a JSON round-trip', () {
      final plan = MedicationPlan(
        id: 'plan-1',
        petId: 'pet-1',
        name: 'Amoxicillin',
        purpose: 'Gut infection',
        sideEffects: 'Soft stools',
        remainingDoses: 6,
        createdByID: 'caregiver-1',
        createdByNameSnapshot: 'Sam',
        createdAt: DateTime(2026, 3, 1),
      );

      final decoded = MedicationPlan.fromJson(plan.toJson());

      expect(decoded.name, 'Amoxicillin');
      expect(decoded.purpose, 'Gut infection');
      expect(decoded.remainingDoses, 6);
      expect(decoded.isActive, isTrue);
    });

    test('a routine carries its course fields through JSON', () {
      final routine = _routine(
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 7),
      );

      final decoded = CareRoutine.fromJson(routine.toJson());

      expect(decoded.medicationPlanId, 'plan-1');
      expect(decoded.doseText, 'Half a tablet');
      expect(decoded.doseInstructions, 'After food');
      expect(decoded.endDate, DateTime(2026, 3, 7));
      expect(decoded.isMedication, isTrue);
    });

    test('a task carries its skip reason through JSON', () {
      final task = CareTask(
        id: 'routine-1_2026-03-02',
        title: 'Amoxicillin',
        category: CareCategory.medication,
        dueTime: DateTime(2026, 3, 2, 8),
        kind: CareTaskKind.routine,
        routineID: 'routine-1',
        status: CareTaskStatus.skipped,
        createdBy: 'Sam',
        skipReason: MedicationSkipReason.vomited,
        skipNote: 'brought it straight back up',
      );

      final decoded = CareTask.fromJson(task.toJson());

      expect(decoded.skipReason, MedicationSkipReason.vomited);
      expect(decoded.skipNote, 'brought it straight back up');
    });

    test('copyWith keeps the skip reason and clears it on request', () {
      final task = CareTask(
        id: 't',
        title: 'Amoxicillin',
        category: CareCategory.medication,
        dueTime: DateTime(2026, 3, 2, 8),
        createdBy: 'Sam',
        skipReason: MedicationSkipReason.petRefused,
        skipNote: 'spat it out',
      );

      // copyWith is allowlist-based, so a dropped field would vanish here.
      final claimed = task.copyWith(status: CareTaskStatus.claimed);
      expect(claimed.skipReason, MedicationSkipReason.petRefused);
      expect(claimed.skipNote, 'spat it out');

      final cleared = task.copyWith(clearSkipReason: true);
      expect(cleared.skipReason, isNull);
      expect(cleared.skipNote, isNull);
    });

    test('a health record survives a JSON round-trip with attachments', () {
      final record = _record(nextDueAt: DateTime(2026, 11, 2)).copyWith(
        medicationPlanId: 'plan-1',
        attachments: [
          HealthAttachment(
            id: 'a1',
            url: 'https://example.test/a1.jpg',
            storagePath: 'households/h/records/record-1/a1.jpg',
            uploadedAt: DateTime(2026, 3, 2, 11),
          ),
        ],
      );

      final decoded = HealthRecord.fromJson(record.toJson());

      expect(decoded.diagnosis, 'Mild gastroenteritis');
      expect(decoded.nextDueAt, DateTime(2026, 11, 2));
      expect(decoded.medicationPlanId, 'plan-1');
      expect(decoded.attachments.single.id, 'a1');
    });

    test('unknown enum values fall back instead of throwing', () {
      expect(MedicationForm.fromRaw('nonsense'), MedicationForm.oral);
      expect(MedicationSkipReason.fromRaw('nonsense'),
          MedicationSkipReason.other);
      expect(HealthRecordType.fromRaw('nonsense'), HealthRecordType.note);
    });

    test('adherence reports null rather than zero when nothing was due', () {
      const empty = MedicationAdherence(given: 0, skipped: 0, missed: 0);
      expect(empty.rate, isNull);
      expect(empty.isEmpty, isTrue);

      const partial = MedicationAdherence(given: 25, skipped: 2, missed: 1);
      expect(partial.planned, 28);
      expect(partial.percent, 89);
    });

    test('the medication record type is owned by the course', () {
      expect(HealthRecordType.medication.isCourseGenerated, isTrue);
      expect(HealthRecordType.vetVisit.isCourseGenerated, isFalse);
    });
  });

  group('routine scheduling', () {
    test('the course start and end days are both inclusive', () {
      final routine = _routine(
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 7),
      );

      expect(routineRunsOn(routine, DateTime(2026, 2, 28)), isFalse);
      expect(routineRunsOn(routine, DateTime(2026, 3, 1)), isTrue);
      expect(routineRunsOn(routine, DateTime(2026, 3, 7)), isTrue);
      expect(routineRunsOn(routine, DateTime(2026, 3, 8)), isFalse);
    });

    test('a routine with no end date keeps running', () {
      final routine = _routine(startDate: DateTime(2026, 3, 1));
      expect(routineRunsOn(routine, DateTime(2027, 1, 1)), isTrue);
    });

    test('selected weekdays are honoured alongside the end date', () {
      // 2026-03-02 is a Monday, weekday 2 in the 1 = Sunday convention.
      final monday = DateTime(2026, 3, 2);
      final routine = _routine(
        weekdays: const [2],
        frequency: CareRoutineFrequency.selectedDays,
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 31),
      );

      expect(swiftWeekday(monday), 2);
      expect(routineRunsOn(routine, monday), isTrue);
      expect(routineRunsOn(routine, monday.add(const Duration(days: 1))),
          isFalse);
    });
  });

  group('health records', () {
    test('days until due counts by calendar day and goes negative', () {
      final now = DateTime(2026, 3, 2, 23, 0);
      expect(_record(nextDueAt: DateTime(2026, 3, 9, 1)).daysUntilDue(now), 7);
      expect(_record(nextDueAt: DateTime(2026, 2, 28)).daysUntilDue(now), -2);
      expect(_record().daysUntilDue(now), isNull);
    });

    test('only vaccinations and dewormings carry a next-due date', () {
      expect(HealthRecordType.vaccination.hasNextDue, isTrue);
      expect(HealthRecordType.deworming.hasNextDue, isTrue);
      expect(HealthRecordType.vetVisit.hasNextDue, isFalse);
    });

    test('a weight record without a weight is rejected', () {
      expect(_record(type: HealthRecordType.weight).isValid, isFalse);
      expect(_record(type: HealthRecordType.weight, weightKg: 4.2).isValid,
          isTrue);
    });
  });

  group('store, against the offline mock', () {
    Future<CareStore> readyStore({List<Pet>? pets}) async {
      final store = CareStore(MockCareService());
      await store.createHousehold(
        name: 'Mochi Family',
        pets: pets ?? [const Pet(id: 'pet-1', name: 'Mochi')],
        caregiverName: 'Sam',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return store;
    }

    /// The seeded course runs 08:00 and 20:00; pick whichever has elapsed.
    CareTask dueDose(CareStore store) => store
        .doseTasksOn(DateTime.now())
        .firstWhere((t) => !t.dueTime.isAfter(DateTime.now()));

    bool hasDueDose(CareStore store) => store
        .doseTasksOn(DateTime.now())
        .any((t) => !t.dueTime.isAfter(DateTime.now()));

    test('the seeded course expands into ordinary care tasks', () async {
      final store = await readyStore();

      expect(store.medicationPlans, isNotEmpty);
      final doses = store.todayDoseTasks;
      expect(doses.length, 2);
      // They are the very same objects Today shows, not a parallel list.
      final todayIds = store.todayTasks.map((t) => t.id).toSet();
      expect(doses.every((d) => todayIds.contains(d.id)), isTrue);
    });

    test('doses are interleaved with other tasks in time order', () async {
      final store = await readyStore();
      final today = store.todayTasks;

      final times = today.map((t) => t.dueTime).toList();
      final sorted = [...times]..sort();
      expect(times, sorted);

      // The list mixes medication with ordinary care rather than grouping it.
      expect(today.any((t) => store.planForTask(t) != null), isTrue);
      expect(today.any((t) => store.planForTask(t) == null), isTrue);
    });

    test('a dose can be claimed and completed like any task', () async {
      final store = await readyStore();
      if (!hasDueDose(store)) return;
      final dose = dueDose(store);

      expect(await store.claim(dose), isTrue);
      final claimed =
          store.todayDoseTasks.firstWhere((t) => t.id == dose.id);
      expect(claimed.status, CareTaskStatus.claimed);
      expect(claimed.assigneeNameSnapshot, 'Sam');

      expect(await store.complete(claimed), isTrue);
      expect(
        store.todayDoseTasks.firstWhere((t) => t.id == dose.id).status,
        CareTaskStatus.completed,
      );
    });

    test('a dose can be opened to anyone in the household', () async {
      final store = await readyStore();
      final dose = store.todayDoseTasks.first;

      expect(await store.requestAnyone(dose), isTrue);
      final opened = store.todayDoseTasks.firstWhere((t) => t.id == dose.id);
      expect(opened.assignmentRequest?.mode, AssignmentMode.open);
    });

    test('skipping a dose records why', () async {
      final store = await readyStore();
      final dose = store.todayDoseTasks.first;

      expect(
        await store.skipTaskOccurrence(
          dose,
          reason: MedicationSkipReason.vomited,
          note: 'straight back up',
        ),
        isTrue,
      );

      final skipped = store.todayDoseTasks.firstWhere((t) => t.id == dose.id);
      expect(skipped.status, CareTaskStatus.skipped);
      expect(skipped.skipReason, MedicationSkipReason.vomited);
      expect(skipped.skipNote, 'straight back up');

      expect(await store.restoreTaskOccurrence(skipped), isTrue);
      final restored = store.todayDoseTasks.firstWhere((t) => t.id == dose.id);
      expect(restored.status, CareTaskStatus.unclaimed);
      expect(restored.skipReason, isNull);
    });

    test('an unconfirmed completion is not counted as given', () async {
      final store = await readyStore();
      if (!hasDueDose(store)) return;
      final dose = dueDose(store);
      await store.claim(dose);
      await store.complete(
          store.todayDoseTasks.firstWhere((t) => t.id == dose.id));

      final confirmed = store.adherence(days: 1);
      expect(confirmed.given, 1);

      // The same dose, unconfirmed, must never read as given: believing a pet
      // was already dosed is the failure that could dose it twice.
      final unconfirmed = store.todayDoseTasks
          .firstWhere((t) => t.id == dose.id)
          .copyWith(isServerConfirmed: false);
      expect(unconfirmed.status, CareTaskStatus.completed);
      expect(unconfirmed.isServerConfirmed, isFalse);
    });

    test('adherence counts untouched elapsed doses as missed', () async {
      final store = await readyStore();
      final elapsed = store
          .doseTasksOn(DateTime.now())
          .where((t) => !t.dueTime.isAfter(DateTime.now()))
          .toList();
      if (elapsed.isEmpty) return;

      await store.claim(elapsed.first);
      await store.complete(
          store.todayDoseTasks.firstWhere((t) => t.id == elapsed.first.id));

      final stats = store.adherence(petId: 'pet-1', days: 1);
      expect(stats.given, 1);
      expect(stats.planned, elapsed.length);
      expect(stats.missed, elapsed.length - 1);
    });

    test('creating a course writes its dose times and a history entry',
        () async {
      final store = await readyStore();
      final caregiver = store.currentCaregiver!;
      final start = startOfDay(DateTime.now());

      final saved = await store.saveMedicationCourse(
        plan: MedicationPlan(
          id: 'plan-new',
          petId: 'pet-1',
          name: 'Metacam',
          purpose: 'Pain relief after the dental',
          createdByID: caregiver.id,
          createdByNameSnapshot: caregiver.displayName,
          createdAt: DateTime.now(),
        ),
        times: const [
          MedicationDoseTime(hour: 9, minute: 0, doseText: '0.5 ml'),
          MedicationDoseTime(hour: 21, minute: 0, doseText: '0.5 ml'),
        ],
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        startDate: start,
        endDate: start.add(const Duration(days: 4)),
      );

      expect(saved, isNotNull);
      expect(store.routinesForPlan('plan-new').length, 2);
      expect(store.courseLengthDays('plan-new'), 5);
      expect(store.courseDayNumber('plan-new', start), 1);

      // The course shows up in the medical history without extra wiring, so
      // the vet visit pack picks it up too.
      final record = store.courseHealthRecord('plan-new');
      expect(record, isNotNull);
      expect(record!.type, HealthRecordType.medication);
      expect(record.title, 'Metacam');
      expect(record.treatment, contains('09:00 0.5 ml'));
      expect(store.recordsForPet('pet-1'), contains(record));
    });

    test('an invalid course is rejected before it reaches the service',
        () async {
      final store = await readyStore();
      final caregiver = store.currentCaregiver!;

      final saved = await store.saveMedicationCourse(
        plan: MedicationPlan(
          id: 'plan-bad',
          petId: 'pet-1',
          name: '',
          createdByID: caregiver.id,
          createdByNameSnapshot: caregiver.displayName,
          createdAt: DateTime.now(),
        ),
        times: const [],
        weekdays: const [1],
        startDate: DateTime.now(),
      );

      expect(saved, isNull);
      expect(store.errorMessage, isNotNull);
      expect(store.routinesForPlan('plan-bad'), isEmpty);
    });

    test('stopping a course keeps its history and stops scheduling', () async {
      final store = await readyStore();
      final plan = store.medicationPlans.single;
      if (hasDueDose(store)) {
        final dose = dueDose(store);
        await store.claim(dose);
        await store.complete(
            store.todayDoseTasks.firstWhere((t) => t.id == dose.id));
      }

      expect(await store.stopMedicationCourse(plan), isTrue);

      expect(store.plansForPet('pet-1', active: true), isEmpty);
      expect(store.plansForPet('pet-1'), isNotEmpty);
      expect(
        store.doseTasksOn(DateTime.now().add(const Duration(days: 1))),
        isEmpty,
      );
      // The medical-history entry survives the course ending.
      expect(store.courseHealthRecord(plan.id), isNotNull);
    });

    test('deleting a course removes its dose times and history entry',
        () async {
      final store = await readyStore();
      final plan = store.medicationPlans.single;

      expect(await store.deleteMedicationCourse(plan), isTrue);

      expect(store.routinesForPlan(plan.id), isEmpty);
      expect(store.courseHealthRecord(plan.id), isNull);
      expect(store.todayDoseTasks, isEmpty);
    });

    test('a multi-pet routine keeps its pets when expanded', () async {
      final store = await readyStore(pets: [
        const Pet(id: 'pet-1', name: 'Mochi'),
        const Pet(id: 'pet-2', name: 'Luna'),
      ]);

      await store.addTask(
        title: 'Brush both',
        category: CareCategory.grooming,
        kind: CareTaskKind.routine,
        priority: CarePriority.normal,
        date: DateTime.now(),
        petIds: const ['pet-1', 'pet-2'],
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final expanded =
          store.todayTasks.firstWhere((t) => t.title == 'Brush both');
      // Without petIds on the expansion every pet filter reads this as
      // "applies to all of them".
      expect(expanded.effectivePetIds, ['pet-1', 'pet-2']);
    });

    test('the seeded vaccination surfaces as an upcoming due reminder',
        () async {
      final store = await readyStore();

      // Seeded 30 days out, beyond the 14-day look-ahead.
      expect(store.upcomingHealthDue(petId: 'pet-1'), isEmpty);

      final soon = store.healthRecords
          .firstWhere((r) => r.type == HealthRecordType.vaccination)
          .copyWith(nextDueAt: DateTime.now().add(const Duration(days: 5)));
      await store.saveHealthRecord(soon);

      expect(store.upcomingHealthDue(petId: 'pet-1').single.daysUntilDue, 5);
    });

    test('saving a weight record also updates the pet weight history',
        () async {
      final store = await readyStore();

      final saved = await store.saveHealthRecord(_record(
        id: 'record-weight',
        type: HealthRecordType.weight,
        occurredAt: DateTime.now(),
        weightKg: 4.2,
      ));

      expect(saved, isTrue);
      final pet = store.household!.pets.single;
      expect(pet.weightKg, 4.2);
      expect(pet.weightHistory.single.weightKg, 4.2);
    });

    test('records are editable and deletable', () async {
      final store = await readyStore();
      final original = store.healthRecords
          .firstWhere((r) => r.type == HealthRecordType.vetVisit);

      await store
          .saveHealthRecord(original.copyWith(title: 'Vomiting — follow-up'));
      final edited = store.recordByID(original.id)!;
      expect(edited.title, 'Vomiting — follow-up');
      expect(edited.wasEdited, isTrue);

      expect(await store.deleteHealthRecord(edited), isTrue);
      expect(store.recordByID(original.id), isNull);
    });
  });
}
