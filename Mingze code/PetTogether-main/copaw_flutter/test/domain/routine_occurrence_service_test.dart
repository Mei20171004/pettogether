import 'package:copaw_flutter/src/domain/models.dart';
import 'package:copaw_flutter/src/domain/routine_occurrence_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = RoutineOccurrenceService();

  test('daily occurrence uses household timezone and stable ID', () {
    final tasks = service.tasksForDay(
      selectedInstant: DateTime.utc(2026, 8, 12, 18),
      householdTimeZoneIdentifier: 'Asia/Tokyo',
      routines: [_routine()],
      persistedTasks: const [],
    );

    expect(tasks.single.id, 'routine-1_2026-08-13');
    expect(tasks.single.dueTime, DateTime.utc(2026, 8, 12, 23));
  });

  test('selected weekdays use legacy Sunday-one numbering', () {
    final routine = _routine(
      frequency: CareRoutineFrequency.selectedDays,
      weekdays: const [1],
    );

    expect(
      service.tasksForDay(
        selectedInstant: DateTime.utc(2026, 8, 16, 3),
        householdTimeZoneIdentifier: 'Asia/Tokyo',
        routines: [routine],
        persistedTasks: const [],
      ),
      hasLength(1),
    );
    expect(
      service.tasksForDay(
        selectedInstant: DateTime.utc(2026, 8, 17, 3),
        householdTimeZoneIdentifier: 'Asia/Tokyo',
        routines: [routine],
        persistedTasks: const [],
      ),
      isEmpty,
    );
  });

  test('start-date boundary excludes prior local day', () {
    final routine = _routine(startDate: DateTime.utc(2026, 8, 15, 15));

    expect(
      service.tasksForDay(
        selectedInstant: DateTime.utc(2026, 8, 15, 3),
        householdTimeZoneIdentifier: 'Asia/Tokyo',
        routines: [routine],
        persistedTasks: const [],
      ),
      isEmpty,
    );
  });

  test('persisted occurrence wins over virtual routine', () {
    final persisted = _task(
      id: 'routine-1_2026-08-13',
      title: 'Server version',
      dueTime: DateTime.utc(2026, 8, 12, 23),
    );
    final tasks = service.tasksForDay(
      selectedInstant: DateTime.utc(2026, 8, 12, 18),
      householdTimeZoneIdentifier: 'Asia/Tokyo',
      routines: [_routine()],
      persistedTasks: [persisted],
    );

    expect(tasks, hasLength(1));
    expect(tasks.single.title, 'Server version');
  });

  test('DST transition still emits one occurrence on the local day', () {
    final routine = _routine(hour: 2, minute: 30);
    final tasks = service.tasksForDay(
      selectedInstant: DateTime.utc(2026, 3, 8, 16),
      householdTimeZoneIdentifier: 'America/New_York',
      routines: [routine],
      persistedTasks: const [],
    );

    expect(tasks, hasLength(1));
    expect(tasks.single.id, 'routine-1_2026-03-08');
  });
}

CareRoutine _routine({
  CareRoutineFrequency frequency = CareRoutineFrequency.daily,
  List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
  int hour = 8,
  int minute = 0,
  DateTime? startDate,
}) => CareRoutine(
  id: 'routine-1',
  title: 'Breakfast',
  category: CareCategory.feeding,
  priority: CarePriority.normal,
  frequency: frequency,
  weekdays: weekdays,
  hour: hour,
  minute: minute,
  startDate: startDate ?? DateTime.utc(2026),
  timeZoneIdentifier: 'Asia/Tokyo',
  createdById: 'user-1',
  createdByNameSnapshot: 'Alex',
  isActive: true,
);

CareTask _task({
  required String id,
  required String title,
  required DateTime dueTime,
}) => CareTask(
  id: id,
  title: title,
  category: CareCategory.feeding,
  dueTime: dueTime,
  kind: CareTaskKind.routine,
  priority: CarePriority.normal,
  routineId: 'routine-1',
  status: CareTaskStatus.claimed,
  assignmentRequest: null,
  assigneeId: 'user-1',
  assigneeNameSnapshot: 'Alex',
  claimedAt: dueTime,
  createdById: 'user-1',
  createdBy: 'Alex',
  createdAt: DateTime.utc(2026),
  completedById: null,
  completedBy: null,
  completedAt: null,
  revision: 1,
);
