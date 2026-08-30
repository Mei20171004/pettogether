import 'package:flutter/material.dart';

import '../data/notification_center_repository.dart';
import '../domain/notification_models.dart';
import '../localization/app_locale.dart';
import '../theme/copaw_theme.dart';

enum NotificationUpdatesSection { changes, reminders }

enum NotificationPreferenceField {
  medication,
  assignment,
  urgent,
  push,
  quietHours,
  summary,
}

enum NotificationPreferenceMinuteField { quietStart, quietEnd, summary }

class NotificationUpdatesSwitcher extends StatelessWidget {
  const NotificationUpdatesSwitcher({
    required this.strings,
    required this.selection,
    required this.changesUnread,
    required this.remindersUnread,
    required this.onChanged,
    super.key,
  });

  final AppStrings strings;
  final NotificationUpdatesSection selection;
  final bool changesUnread;
  final bool remindersUnread;
  final ValueChanged<NotificationUpdatesSection> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _UpdatesChoice(
            key: const Key('notificationUpdates.changes'),
            label: strings.notificationChanges,
            selected: selection == NotificationUpdatesSection.changes,
            unread: changesUnread,
            onTap: () => onChanged(NotificationUpdatesSection.changes),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _UpdatesChoice(
            key: const Key('notificationUpdates.reminders'),
            label: strings.notificationReminders,
            selected: selection == NotificationUpdatesSection.reminders,
            unread: remindersUnread,
            onTap: () => onChanged(NotificationUpdatesSection.reminders),
          ),
        ),
      ],
    ),
  );
}

class _UpdatesChoice extends StatelessWidget {
  const _UpdatesChoice({
    required this.label,
    required this.selected,
    required this.unread,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    onTap: onTap,
    label: unread
        ? '$label, ${AppStrings(_localeOf(context)).notificationUnread}'
        : label,
    child: ExcludeSemantics(
      child: Material(
        color: selected ? CopawColors.lavender : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (unread) ...[
                    const SizedBox(width: 6),
                    const SizedBox.square(
                      dimension: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: CopawColors.purple,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class NotificationInboxCard extends StatelessWidget {
  const NotificationInboxCard({
    required this.strings,
    required this.page,
    required this.loading,
    required this.errorMessage,
    required this.onRetry,
    required this.onLoadMore,
    this.pinnedItem,
    this.loadingMore = false,
    this.onOpenItem,
    super.key,
  });

  final AppStrings strings;
  final NotificationInboxPage? page;
  final NotificationInboxItem? pinnedItem;
  final bool loading;
  final bool loadingMore;
  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final ValueChanged<NotificationInboxItem>? onOpenItem;

  @override
  Widget build(BuildContext context) {
    final byId = <String, NotificationInboxItem>{
      for (final item in page?.items ?? const <NotificationInboxItem>[])
        item.id: item,
    };
    if (pinnedItem case final item?) byId[item.id] = item;
    final items = byId.values.toList(growable: false)
      ..sort((left, right) {
        final time = right.createdAt.compareTo(left.createdAt);
        return time != 0 ? time : right.id.compareTo(left.id);
      });
    final active = items
        .where((item) => item.status == NotificationInboxStatus.active)
        .toList(growable: false);
    return CopawCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.notificationInboxTitle,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(strings.notificationInboxScope),
          if (page?.authority == NotificationObservationAuthority.cached) ...[
            const SizedBox(height: 12),
            _StatusMessage(
              key: const Key('notificationInbox.cached'),
              message: strings.notificationInboxCached,
            ),
          ],
          if ((page?.droppedItemCount ?? 0) > 0) ...[
            const SizedBox(height: 12),
            _StatusMessage(
              key: const Key('notificationInbox.dropped'),
              message: strings.notificationInboxDropped,
            ),
          ],
          if (page?.hasPendingWrites == true) ...[
            const SizedBox(height: 12),
            _StatusMessage(
              key: const Key('notificationInbox.pending'),
              message: strings.notificationInboxPending,
            ),
          ],
          if (errorMessage case final message?) ...[
            const SizedBox(height: 12),
            _StatusMessage(message: message, isError: true),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('notificationInbox.retry'),
              onPressed: onRetry,
              child: Text(strings.retry),
            ),
          ],
          const SizedBox(height: 12),
          if (loading && items.isEmpty)
            const Center(
              child: CircularProgressIndicator(
                key: Key('notificationInbox.loading'),
              ),
            )
          else if (active.isEmpty &&
              errorMessage == null &&
              (page?.droppedItemCount ?? 0) == 0 &&
              page?.authority ==
                  NotificationObservationAuthority.serverConfirmed &&
              page?.hasPendingWrites == false)
            Text(
              strings.notificationInboxEmpty,
              key: const Key('notificationInbox.empty'),
            )
          else
            for (final item in items)
              _InboxRow(
                item: item,
                strings: strings,
                cached:
                    item != pinnedItem &&
                    page?.authorityFor(item) ==
                        NotificationObservationAuthority.cached,
                onOpen: onOpenItem == null ? null : () => onOpenItem!(item),
              ),
          if (page?.mayHaveMore == true) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('notificationInbox.loadMore'),
              onPressed: loadingMore ? null : onLoadMore,
              icon: loadingMore
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(strings.loadOlderReminders),
            ),
          ],
        ],
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({
    required this.item,
    required this.strings,
    required this.cached,
    required this.onOpen,
  });

  final NotificationInboxItem item;
  final AppStrings strings;
  final bool cached;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final available = item.status == NotificationInboxStatus.active;
    final label = available
        ? strings.notificationInboxItem(item.category)
        : strings.notificationInboxUnavailable;
    final reason = strings.notificationRouteReason(item.routeReason);
    final action = available ? onOpen : null;
    return Semantics(
      button: action != null,
      enabled: action != null,
      onTap: action,
      label: available
          ? '$label. $reason${cached ? '. ${strings.notificationInboxCachedItem}' : ''}'
          : label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: action,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              key: Key('notificationInbox.item.${item.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: available
                    ? CopawColors.lavender.withValues(alpha: 0.45)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (available) Text(reason),
                  if (cached) Text(strings.notificationInboxCachedItem),
                  if (action != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        strings.notificationOpenReminder,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationProfileCard extends StatelessWidget {
  const NotificationProfileCard({
    required this.strings,
    required this.capability,
    required this.providerSnapshot,
    required this.preferences,
    required this.memberNamesById,
    required this.saving,
    required this.mutationError,
    required this.onEnablePermission,
    required this.onOpenSettings,
    required this.onRetryDevice,
    required this.onRetryPreferences,
    required this.onRetryPreferenceSave,
    required this.onRepairPreferences,
    required this.onPreferenceChanged,
    required this.onBackupChanged,
    required this.onMinuteChanged,
    super.key,
  });

  final AppStrings strings;
  final NotificationCapability capability;
  final NotificationProviderEvidenceSnapshot? providerSnapshot;
  final HouseholdNotificationPreferences? preferences;
  final Map<String, String> memberNamesById;
  final bool saving;
  final String? mutationError;
  final VoidCallback onEnablePermission;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetryDevice;
  final VoidCallback onRetryPreferences;
  final VoidCallback onRetryPreferenceSave;
  final VoidCallback onRepairPreferences;
  final void Function(NotificationPreferenceField field, bool value)
  onPreferenceChanged;
  final ValueChanged<Set<String>> onBackupChanged;
  final void Function(NotificationPreferenceMinuteField field, int minute)
  onMinuteChanged;

  @override
  Widget build(BuildContext context) {
    final preferenceMessage = switch (capability.preferenceAuthority) {
      NotificationPreferenceAuthority.missingDefaults =>
        strings.notificationPreferencesMissing,
      NotificationPreferenceAuthority.serverConfirmed => '',
      NotificationPreferenceAuthority.cached =>
        strings.notificationPreferencesCached,
      NotificationPreferenceAuthority.pendingWrite =>
        strings.notificationPreferencesPending,
      NotificationPreferenceAuthority.malformed =>
        strings.notificationPreferencesMalformed,
      NotificationPreferenceAuthority.error =>
        strings.notificationPreferencesError,
    };
    return CopawCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.notifications,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _LayerStatus(
            label: strings.notificationOsPermission,
            value: _permissionCopy(strings, capability.osPermission),
          ),
          _LayerStatus(
            label: strings.notificationInstallation,
            value: _readinessCopy(strings, capability.installationReadiness),
          ),
          _LayerStatus(
            label: strings.notificationProviderEvidence,
            value: _providerCopy(strings, capability, providerSnapshot),
          ),
          _LayerStatus(
            label: strings.notificationProviderScopeLabel,
            value: strings.notificationProviderScope,
          ),
          if (providerSnapshot?.attemptCount case final count? when count > 0)
            _LayerStatus(
              label: strings.notificationProviderAttemptTime,
              value: providerSnapshot?.updatedAt == null
                  ? strings.notificationProviderAttemptTimeUnknown
                  : _formatProviderAttempt(
                      context,
                      providerSnapshot!.updatedAt!,
                    ),
            ),
          _LayerStatus(
            label: strings.notificationPreferences,
            value: preferenceMessage,
          ),
          if (capability.osPermission == NotificationOsPermission.notDetermined)
            FilledButton(
              key: const Key('notifications.enable'),
              onPressed: onEnablePermission,
              child: Text(strings.enableNotifications),
            )
          else if (capability.osPermission == NotificationOsPermission.denied)
            OutlinedButton(
              key: const Key('notifications.settings'),
              onPressed: onOpenSettings,
              child: Text(strings.openNotificationSettings),
            )
          else if (capability.osPermission == NotificationOsPermission.error ||
              capability.installationReadiness ==
                  NotificationInstallationReadiness.error ||
              capability.installationReadiness ==
                  NotificationInstallationReadiness.unavailable)
            OutlinedButton(
              key: const Key('notifications.retry'),
              onPressed: onRetryDevice,
              child: Text(strings.retryNotifications),
            ),
          if (capability.preferenceAuthority ==
              NotificationPreferenceAuthority.malformed) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('notifications.preferences.repair'),
              onPressed: saving ? null : onRepairPreferences,
              child: Text(strings.repairNotificationPreferences),
            ),
          ] else if (capability.preferenceAuthority ==
              NotificationPreferenceAuthority.error) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('notifications.preferences.retry'),
              onPressed: saving ? null : onRetryPreferences,
              child: Text(strings.retry),
            ),
          ],
          if (mutationError case final message?) ...[
            const SizedBox(height: 8),
            _StatusMessage(message: message, isError: true),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('notifications.preferences.saveRetry'),
              onPressed: saving ? null : onRetryPreferenceSave,
              child: Text(strings.retry),
            ),
          ],
          if (preferences case final value?) ...[
            const SizedBox(height: 12),
            _PreferenceSwitch(
              key: const Key('notifications.preferences.medication'),
              label: strings.notificationMedicationPreference,
              value: value.medicationRemindersEnabled,
              enabled: !saving,
              onChanged: (next) => onPreferenceChanged(
                NotificationPreferenceField.medication,
                next,
              ),
            ),
            _PreferenceSwitch(
              key: const Key('notifications.preferences.assignment'),
              label: strings.notificationAssignmentPreference,
              value: value.assignmentAlertsEnabled,
              enabled: !saving,
              onChanged: (next) => onPreferenceChanged(
                NotificationPreferenceField.assignment,
                next,
              ),
            ),
            _PreferenceSwitch(
              key: const Key('notifications.preferences.urgent'),
              label: strings.notificationUrgentPreference,
              value: value.urgentAlertsEnabled,
              enabled: !saving,
              onChanged: (next) =>
                  onPreferenceChanged(NotificationPreferenceField.urgent, next),
            ),
            _PreferenceSwitch(
              key: const Key('notifications.preferences.push'),
              label: strings.notificationPushPreference,
              value: value.pushEnabled,
              enabled: !saving,
              onChanged: (next) =>
                  onPreferenceChanged(NotificationPreferenceField.push, next),
            ),
            _PreferenceSwitch(
              key: const Key('notifications.preferences.quiet'),
              label: strings.notificationQuietPreference,
              value: value.quietHoursEnabled,
              enabled: !saving,
              onChanged: (next) => onPreferenceChanged(
                NotificationPreferenceField.quietHours,
                next,
              ),
            ),
            if (value.quietHoursEnabled) ...[
              _MinuteButton(
                key: const Key('notifications.preferences.quietStart'),
                label: strings.notificationQuietStart,
                minute: value.quietStartMinute,
                enabled: !saving,
                onChanged: (minute) => onMinuteChanged(
                  NotificationPreferenceMinuteField.quietStart,
                  minute,
                ),
              ),
              _MinuteButton(
                key: const Key('notifications.preferences.quietEnd'),
                label: strings.notificationQuietEnd,
                minute: value.quietEndMinute,
                enabled: !saving,
                onChanged: (minute) => onMinuteChanged(
                  NotificationPreferenceMinuteField.quietEnd,
                  minute,
                ),
              ),
            ],
            _PreferenceSwitch(
              key: const Key('notifications.preferences.summary'),
              label: strings.notificationSummaryPreference,
              value: value.summaryEnabled,
              enabled: !saving,
              onChanged: (next) => onPreferenceChanged(
                NotificationPreferenceField.summary,
                next,
              ),
            ),
            if (value.summaryEnabled)
              _MinuteButton(
                key: const Key('notifications.preferences.summaryMinute'),
                label: strings.notificationSummaryTime,
                minute: value.summaryMinute,
                enabled: !saving,
                onChanged: (minute) => onMinuteChanged(
                  NotificationPreferenceMinuteField.summary,
                  minute,
                ),
              ),
            if (value.backupForMemberIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${strings.notificationBackupPreference}: '
                '${value.backupForMemberIds.map((id) => memberNamesById[id] ?? id).join(', ')}',
              ),
            ],
            if (memberNamesById.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                strings.notificationBackupPreference,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              for (final entry in memberNamesById.entries)
                Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    key: Key('notifications.preferences.backup.${entry.key}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value),
                    value: value.backupForMemberIds.contains(entry.key),
                    onChanged: saving
                        ? null
                        : (selected) {
                            final next = value.backupForMemberIds.toSet();
                            if (selected == true) {
                              next.add(entry.key);
                            } else {
                              next.remove(entry.key);
                            }
                            onBackupChanged(next);
                          },
                  ),
                ),
            ],
          ],
          if (saving) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              key: Key('notifications.preferences.saving'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MinuteButton extends StatelessWidget {
  const _MinuteButton({
    required this.label,
    required this.minute,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String label;
  final int minute;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
    final value = MaterialLocalizations.of(context).formatTimeOfDay(time);
    Future<void> pickTime() async {
      final selected = await showTimePicker(
        context: context,
        initialTime: time,
      );
      if (selected != null) {
        onChanged(selected.hour * 60 + selected.minute);
      }
    }

    return Semantics(
      button: true,
      enabled: enabled,
      onTap: enabled ? pickTime : null,
      label: '$label. $value',
      child: ExcludeSemantics(
        child: OutlinedButton(
          onPressed: enabled ? pickTime : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Text(label), Text(value)],
          ),
        ),
      ),
    );
  }
}

class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: enabled ? onChanged : null,
    ),
  );
}

class _LayerStatus extends StatelessWidget {
  const _LayerStatus({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      label: '$label. $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (value.isNotEmpty) Text(value),
          ],
        ),
      ),
    ),
  );
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.message,
    this.isError = false,
    super.key,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: isError,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isError
            ? Theme.of(context).colorScheme.errorContainer
            : CopawColors.lavender.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message),
    ),
  );
}

String _permissionCopy(AppStrings strings, NotificationOsPermission value) =>
    switch (value) {
      NotificationOsPermission.notDetermined =>
        strings.notificationOsNotDetermined,
      NotificationOsPermission.denied => strings.notificationOsDenied,
      NotificationOsPermission.authorized => strings.notificationOsAuthorized,
      NotificationOsPermission.provisional => strings.notificationOsProvisional,
      NotificationOsPermission.unsupported => strings.notificationOsUnsupported,
      NotificationOsPermission.error => strings.notificationOsError,
    };

String _readinessCopy(
  AppStrings strings,
  NotificationInstallationReadiness value,
) => switch (value) {
  NotificationInstallationReadiness.disabled =>
    strings.notificationInstallationDisabled,
  NotificationInstallationReadiness.registering =>
    strings.notificationInstallationRegistering,
  NotificationInstallationReadiness.ready =>
    strings.notificationInstallationReady,
  NotificationInstallationReadiness.unavailable =>
    strings.notificationInstallationUnavailable,
  NotificationInstallationReadiness.unsupported =>
    strings.notificationInstallationUnsupported,
  NotificationInstallationReadiness.error =>
    strings.notificationInstallationError,
};

String _providerCopy(
  AppStrings strings,
  NotificationCapability capability,
  NotificationProviderEvidenceSnapshot? snapshot,
) {
  if (capability.providerEvidence ==
          NotificationProviderEvidence.notVerifiedForCurrentInstallation &&
      const {
        NotificationInstallationReadiness.disabled,
        NotificationInstallationReadiness.unavailable,
        NotificationInstallationReadiness.unsupported,
      }.contains(capability.installationReadiness)) {
    return strings.notificationProviderNotConfigured;
  }
  if (capability.providerAuthority == NotificationObservationAuthority.cached) {
    return strings.notificationProviderCachedUnknown;
  }
  if (capability.providerAuthority ==
      NotificationObservationAuthority.loading) {
    if ((snapshot?.attemptCount ?? 0) == 0) return strings.loading;
    return '${_providerEvidenceCopy(strings, snapshot!.evidence)}\n'
        '${strings.notificationProviderRefreshingStale}';
  }
  if (capability.providerAuthority == NotificationObservationAuthority.error) {
    if ((snapshot?.attemptCount ?? 0) == 0) {
      return strings.notificationProviderUnknown;
    }
    return '${_providerEvidenceCopy(strings, snapshot!.evidence)}\n'
        '${strings.notificationProviderRefreshErrorStale}';
  }
  return _providerEvidenceCopy(strings, capability.providerEvidence);
}

String _providerEvidenceCopy(
  AppStrings strings,
  NotificationProviderEvidence evidence,
) => switch (evidence) {
  NotificationProviderEvidence.notVerifiedForCurrentInstallation =>
    strings.notificationProviderNotVerified,
  NotificationProviderEvidence.providerAccepted =>
    strings.notificationProviderAccepted,
  NotificationProviderEvidence.providerUnknown =>
    strings.notificationProviderUnknown,
  NotificationProviderEvidence.definiteFailure =>
    strings.notificationProviderFailure,
};

String _formatProviderAttempt(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  return '${material.formatCompactDate(local)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

AppLocale _localeOf(BuildContext context) =>
    AppLocale.fromLanguageCode(Localizations.localeOf(context).languageCode);
