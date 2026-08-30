import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/bootstrap/bootstrap_repository.dart';
import 'src/bootstrap/firebase_production_configuration.dart';
import 'src/data/firebase_household_repository.dart';
import 'src/data/firebase_care_task_repository.dart';
import 'src/data/care_task_repository.dart';
import 'src/data/care_task_mutation_repository.dart';
import 'src/data/firebase_care_task_mutation_repository.dart';
import 'src/data/firebase_household_sync_repository.dart';
import 'src/data/firebase_pet_repository.dart';
import 'src/data/firebase_medication_repository.dart';
import 'src/data/household_repository.dart';
import 'src/data/household_sync_repository.dart';
import 'src/data/pet_repository.dart';
import 'src/data/medication_repository.dart';
import 'src/data/firebase_notification_repository.dart';
import 'src/data/firebase_notification_center_gateway.dart';
import 'src/data/firebase_notification_center_repository.dart';
import 'src/data/notification_center_repository.dart';
import 'src/data/notification_interaction_repository.dart';
import 'src/data/notification_lifecycle.dart';
import 'src/data/notification_repository.dart';
import 'src/data/firebase_health_repository.dart';
import 'src/data/health_repository.dart';
import 'src/data/firebase_handoff_repository.dart';
import 'src/data/handoff_repository.dart';
import 'src/data/firebase_handoff_session_repository.dart';
import 'src/data/handoff_session_repository.dart';
import 'src/data/firebase_membership_exit_repository.dart';
import 'src/data/membership_exit_repository.dart';
import 'src/data/firebase_task_responsibility_repository.dart';
import 'src/data/task_responsibility_repository.dart';
import 'src/data/collaboration_event_repository.dart';
import 'src/data/firebase_collaboration_event_repository.dart';
import 'src/data/report_share_repository.dart';
import 'src/data/system_report_share_repository.dart';
import 'src/localization/locale_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runFirebaseCopawApp();
}

void runFirebaseCopawApp({
  BootstrapRepository? bootstrapRepository,
  NotificationRepository? notificationRepository,
  NotificationDeviceRepository? notificationDeviceRepository,
  NotificationPreferencesRepository? notificationPreferencesRepository,
  NotificationInboxRepository? notificationInboxRepository,
  NotificationDeliveryEvidenceRepository? notificationDeliveryRepository,
  NotificationInteractionRepository? notificationInteractionRepository,
  NotificationLifecycleSource notificationLifecycleSource =
      const DisabledNotificationLifecycleSource(),
}) {
  final resolvedNotification =
      notificationRepository ?? FirebaseNotificationRepository();
  final resolvedNotificationDevice =
      notificationDeviceRepository ??
      const ProviderDisabledNotificationDeviceRepository();
  final notificationCenterGateway = FirebaseNotificationCenterGateway();
  runApp(
    ProviderScope(
      overrides: [
        bootstrapRepositoryProvider.overrideWithValue(
          bootstrapRepository ??
              FirebaseBootstrapRepository(options: productionFirebaseOptions()),
        ),
        localeRepositoryProvider.overrideWithValue(
          SharedPreferencesLocaleRepository(),
        ),
        householdRepositoryProvider.overrideWith(
          (ref) => FirebaseHouseholdRepository(),
        ),
        householdSyncRepositoryProvider.overrideWith(
          (ref) => FirebaseHouseholdSyncRepository(),
        ),
        careTaskRepositoryProvider.overrideWith(
          (ref) => FirebaseCareTaskRepository(),
        ),
        careTaskMutationRepositoryProvider.overrideWith(
          (ref) => FirebaseCareTaskMutationRepository(),
        ),
        petRepositoryProvider.overrideWith((ref) => FirebasePetRepository()),
        medicationRepositoryProvider.overrideWith(
          (ref) => FirebaseMedicationRepository(),
        ),
        notificationRepositoryProvider.overrideWith(
          (ref) => resolvedNotification,
        ),
        notificationDeviceRepositoryProvider.overrideWithValue(
          resolvedNotificationDevice,
        ),
        notificationPreferencesRepositoryProvider.overrideWithValue(
          notificationPreferencesRepository ??
              FirebaseNotificationPreferencesRepository(
                gateway: notificationCenterGateway,
              ),
        ),
        notificationInboxRepositoryProvider.overrideWithValue(
          notificationInboxRepository ??
              FirebaseNotificationInboxRepository(
                gateway: notificationCenterGateway,
              ),
        ),
        notificationDeliveryEvidenceRepositoryProvider.overrideWithValue(
          notificationDeliveryRepository ??
              FirebaseNotificationDeliveryEvidenceRepository(
                gateway: notificationCenterGateway,
              ),
        ),
        notificationInteractionRepositoryProvider.overrideWithValue(
          notificationInteractionRepository ??
              StoredNotificationInteractionRepository(
                gateway: notificationCenterGateway,
                store: SharedPreferencesNotificationPendingRouteStore(),
              ),
        ),
        notificationLifecycleSourceProvider.overrideWithValue(
          notificationLifecycleSource,
        ),
        healthRepositoryProvider.overrideWith(
          (ref) => FirebaseHealthRepository(),
        ),
        handoffRepositoryProvider.overrideWith(
          (ref) => FirebaseHandoffRepository(),
        ),
        handoffSessionRepositoryProvider.overrideWith(
          (ref) => FirebaseHandoffSessionRepository(),
        ),
        taskResponsibilityRepositoryProvider.overrideWith(
          (ref) => FirebaseTaskResponsibilityRepository(),
        ),
        membershipExitRepositoryProvider.overrideWith(
          (ref) => FirebaseMembershipExitRepository(),
        ),
        collaborationEventRepositoryProvider.overrideWith(
          (ref) => FirebaseCollaborationEventRepository(),
        ),
        reportShareRepositoryProvider.overrideWith(
          (ref) => SystemReportShareRepository(),
        ),
      ],
      child: const CopawApp(),
    ),
  );
}
