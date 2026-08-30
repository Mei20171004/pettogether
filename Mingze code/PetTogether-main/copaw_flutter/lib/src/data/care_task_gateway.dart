import 'household_data_gateway.dart';

final class CreateOneOffTaskCommand {
  const CreateOneOffTaskCommand({
    required this.householdId,
    required this.taskId,
    required this.title,
    required this.category,
    required this.dueTime,
    required this.priority,
    required this.createdById,
    required this.createdByName,
    required this.petId,
    required this.petName,
  });

  final String householdId;
  final String taskId;
  final String title;
  final String category;
  final DateTime dueTime;
  final String priority;
  final String createdById;
  final String createdByName;
  final String petId;
  final String petName;
}

final class CreateRoutineCommand {
  const CreateRoutineCommand({
    required this.householdId,
    required this.routineId,
    required this.title,
    required this.category,
    required this.priority,
    required this.frequency,
    required this.weekdays,
    required this.hour,
    required this.minute,
    required this.startDate,
    required this.timeZoneIdentifier,
    required this.createdById,
    required this.createdByName,
    required this.petId,
    required this.petName,
  });

  final String householdId;
  final String routineId;
  final String title;
  final String category;
  final String priority;
  final String frequency;
  final List<int> weekdays;
  final int hour;
  final int minute;
  final DateTime startDate;
  final String timeZoneIdentifier;
  final String createdById;
  final String createdByName;
  final String petId;
  final String petName;
}

abstract interface class CareTaskGateway {
  Stream<StoredCareDocuments> observeRoutines(String householdId);
  Stream<StoredCareDocuments> observeTasks(String householdId);
  Future<StoredDocument> readHousehold(String householdId);
  String newTaskId(String householdId);
  String newRoutineId(String householdId);
  Future<void> createOneOffTask(CreateOneOffTaskCommand command);
  Future<void> createRoutine(CreateRoutineCommand command);
}

final class StoredCareDocuments {
  const StoredCareDocuments({
    required this.documents,
    required this.isServerConfirmed,
  });

  final List<StoredDocument> documents;
  final bool isServerConfirmed;
}
