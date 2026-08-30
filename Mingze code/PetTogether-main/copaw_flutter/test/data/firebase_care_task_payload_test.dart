import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:copaw_flutter/src/data/care_task_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_care_task_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const serverTime = _ServerTime();
  final dueTime = DateTime.utc(2026, 8, 12, 10);
  final command = CreateOneOffTaskCommand(
    householdId: 'home-a',
    taskId: 'task-a',
    title: 'Vet call',
    category: 'medication',
    dueTime: dueTime,
    priority: 'urgent',
    createdById: 'user-a',
    createdByName: 'Caregiver',
    petId: 'pet-a',
    petName: 'Mochi',
  );
  final builder = OneOffTaskWritePayloadBuilder(
    serverTimestamp: () => serverTime,
  );

  test('one-off payload is complete and has explicit null overlays', () {
    final payload = builder.build(command);

    expect(payload['id'], 'task-a');
    expect(payload['kind'], 'oneOff');
    expect(payload['status'], 'unclaimed');
    expect(payload['revision'], 0);
    expect(payload['createdAt'], serverTime);
    expect(
      (payload['dueTime'] as Timestamp).millisecondsSinceEpoch,
      dueTime.millisecondsSinceEpoch,
    );
    expect(payload['petID'], 'pet-a');
    expect(payload['petName'], 'Mochi');
    expect(payload.keys, hasLength(34));
    expect(payload['lastCollaborationAction'], 'taskCreated');
    expect(payload['lastCollaborationActorID'], 'user-a');
    expect(payload['lastCollaborationActorName'], 'Caregiver');
    expect(payload['lastCollaborationAt'], serverTime);
    for (final key in [
      'routineID',
      'assignmentRequestID',
      'assignmentMode',
      'requestedByID',
      'requestedByName',
      'requestedToID',
      'requestedToName',
      'assignmentRequestedAt',
      'assigneeID',
      'assigneeName',
      'claimedAt',
      'completedByID',
      'completedBy',
      'completedAt',
      'lastCollaborationTargetID',
      'lastCollaborationTargetName',
      'lastCollaborationRequestID',
    ]) {
      expect(payload.containsKey(key), isTrue, reason: key);
      expect(payload[key], isNull, reason: key);
    }
  });

  test('routine payload matches the Rules-approved 14 fields', () {
    final command = CreateRoutineCommand(
      householdId: 'home-a',
      routineId: 'routine-a',
      title: 'Morning meal',
      category: 'feeding',
      priority: 'normal',
      frequency: 'selectedDays',
      weekdays: const [2, 4, 6],
      hour: 8,
      minute: 30,
      startDate: DateTime.utc(2026, 8, 12),
      timeZoneIdentifier: 'Asia/Tokyo',
      createdById: 'user-a',
      createdByName: 'Caregiver',
      petId: 'pet-a',
      petName: 'Mochi',
    );
    final payload = RoutineWritePayloadBuilder(
      serverTimestamp: () => serverTime,
    ).build(command);

    expect(payload.keys, hasLength(16));
    expect(payload['id'], 'routine-a');
    expect(payload['frequency'], 'selectedDays');
    expect(payload['weekdays'], [2, 4, 6]);
    expect(payload['isActive'], isTrue);
    expect(payload['createdAt'], serverTime);
    expect(payload['petID'], 'pet-a');
    expect(payload['petName'], 'Mochi');
  });
}

final class _ServerTime {
  const _ServerTime();
}
