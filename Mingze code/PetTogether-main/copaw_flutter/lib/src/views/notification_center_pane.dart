import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notification_center_repository.dart';
import '../data/notification_center_gateway.dart';
import '../data/notification_lifecycle.dart';
import '../data/notification_repository.dart';
import '../domain/models.dart';
import '../domain/notification_models.dart';
import '../localization/app_locale.dart';
import 'notification_center_widgets.dart';

enum NotificationCenterPaneMode { hidden, updates, profile }

enum _InboxRetryAction {
  markRead,
  observeCursor,
  observeRecent,
  loadMore,
  resolveRoute,
}

class NotificationCenterPane extends ConsumerStatefulWidget {
  const NotificationCenterPane({
    required this.mode,
    required this.householdId,
    required this.memberId,
    required this.memberJoinedAt,
    required this.timeZoneIdentifier,
    required this.members,
    required this.strings,
    required this.changes,
    required this.changesUnread,
    required this.onUnreadChanged,
    required this.onRouteOpened,
    required this.onRouteRejected,
    required this.onChangesSelected,
    super.key,
  });

  final NotificationCenterPaneMode mode;
  final String householdId;
  final String memberId;
  final DateTime? memberJoinedAt;
  final String? timeZoneIdentifier;
  final List<Caregiver> members;
  final AppStrings strings;
  final Widget changes;
  final bool changesUnread;
  final ValueChanged<bool> onUnreadChanged;
  final VoidCallback onRouteOpened;
  final VoidCallback onRouteRejected;
  final VoidCallback onChangesSelected;

  @override
  ConsumerState<NotificationCenterPane> createState() =>
      _NotificationCenterPaneState();
}

class _NotificationCenterPaneState
    extends ConsumerState<NotificationCenterPane> {
  NotificationUpdatesSection section = NotificationUpdatesSection.changes;
  NotificationInboxPage? page;
  NotificationInboxItem? pinnedItem;
  NotificationReadCursorSnapshot? readCursor;
  NotificationPreferencesSnapshot? preferenceSnapshot;
  NotificationDeviceSnapshot? deviceSnapshot;
  NotificationProviderEvidenceSnapshot? providerSnapshot;
  NotificationPendingRoute? pendingRoute;
  StreamSubscription<NotificationReadCursorSnapshot>? readSubscription;
  StreamSubscription<NotificationInboxPage>? recentSubscription;
  StreamSubscription<NotificationPreferencesSnapshot>? preferenceSubscription;
  StreamSubscription<NotificationProviderEvidenceSnapshot>?
  providerSubscription;
  bool loadingInbox = false;
  bool loadingMore = false;
  bool savingPreferences = false;
  bool markingRead = false;
  bool loadedOlderPage = false;
  String? inboxError;
  String? readError;
  String? cursorError;
  NotificationReadCursor? failedReadCursor;
  NotificationInboxPageCursor? failedPageCursor;
  _InboxRetryAction? inboxRetryAction;
  String? preferenceObservationError;
  String? preferenceMutationError;
  HouseholdNotificationPreferences? preferenceDraft;
  String? mutationSignature;
  String? mutationId;
  String? repairMutationId;
  bool unread = false;
  int _epochCounter = 0;
  late _PaneEpoch _epoch;

  NotificationInboxRepository get _inbox =>
      ref.read(notificationInboxRepositoryProvider);
  NotificationPreferencesRepository get _preferences =>
      ref.read(notificationPreferencesRepositoryProvider);
  NotificationInteractionRepository get _interaction =>
      ref.read(notificationInteractionRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _startEpoch();
  }

  @override
  void didUpdateWidget(NotificationCenterPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.householdId != widget.householdId ||
        oldWidget.memberId != widget.memberId ||
        oldWidget.memberJoinedAt != widget.memberJoinedAt ||
        oldWidget.timeZoneIdentifier != widget.timeZoneIdentifier) {
      _startEpoch();
    }
    if (widget.mode == NotificationCenterPaneMode.updates &&
        section == NotificationUpdatesSection.reminders) {
      _scheduleMarkVisible(_epoch);
    }
  }

  void _startEpoch() {
    final epoch = _PaneEpoch(
      generation: ++_epochCounter,
      householdId: widget.householdId,
      memberId: widget.memberId,
      memberJoinedAt: widget.memberJoinedAt,
      timeZoneIdentifier: widget.timeZoneIdentifier,
    );
    _epoch = epoch;
    unawaited(readSubscription?.cancel());
    unawaited(recentSubscription?.cancel());
    unawaited(preferenceSubscription?.cancel());
    unawaited(providerSubscription?.cancel());
    page = null;
    pinnedItem = null;
    readCursor = null;
    preferenceSnapshot = null;
    deviceSnapshot = null;
    providerSnapshot = null;
    pendingRoute = null;
    loadingInbox = false;
    loadingMore = false;
    savingPreferences = false;
    markingRead = false;
    loadedOlderPage = false;
    inboxError = null;
    readError = null;
    cursorError = null;
    failedReadCursor = null;
    failedPageCursor = null;
    inboxRetryAction = null;
    preferenceObservationError = null;
    preferenceMutationError = null;
    preferenceDraft = null;
    mutationSignature = null;
    mutationId = null;
    repairMutationId = null;
    _setUnread(false, epoch: epoch);
    unawaited(_configureDevice(epoch: epoch));
    final joinedAt = epoch.memberJoinedAt;
    if (joinedAt == null) {
      inboxError = widget.strings.notificationInboxLongError;
      return;
    }
    _observePreferences(epoch);
    _observeReadCursor(epoch);
    _observeRecent(epoch);
    unawaited(_restorePendingRoute(epoch));
    _observeProvider(epoch);
  }

  Future<void> _configureDevice({
    bool request = false,
    _PaneEpoch? epoch,
  }) async {
    final activeEpoch = epoch ?? _epoch;
    final repository = ref.read(notificationDeviceRepositoryProvider);
    try {
      final snapshot = request
          ? await repository.requestDevicePermission(activeEpoch.householdId)
          : await repository.configureDevice(activeEpoch.householdId);
      if (!_isCurrent(activeEpoch)) return;
      setState(() => deviceSnapshot = snapshot);
      if (activeEpoch.memberJoinedAt != null) _observeProvider(activeEpoch);
    } on Object {
      if (!_isCurrent(activeEpoch)) return;
      setState(
        () => deviceSnapshot = const NotificationDeviceSnapshot(
          osPermission: NotificationOsPermission.error,
          installationReadiness: NotificationInstallationReadiness.error,
          installationHash: null,
        ),
      );
    }
  }

  void _observePreferences(_PaneEpoch epoch) {
    unawaited(preferenceSubscription?.cancel());
    if (_isCurrent(epoch)) {
      setStateIfMounted(() => preferenceObservationError = null);
    }
    preferenceSubscription = _preferences
        .observe(
          householdId: epoch.householdId,
          memberId: epoch.memberId,
          memberJoinedAt: epoch.memberJoinedAt!,
          timeZoneIdentifier: epoch.timeZoneIdentifier ?? '',
        )
        .listen(
          (snapshot) {
            if (!_isCurrent(epoch)) return;
            setState(() {
              preferenceSnapshot = snapshot;
              preferenceObservationError = null;
              if (snapshot.authority ==
                  NotificationPreferenceAuthority.serverConfirmed) {
                final observed = snapshot.preferences;
                final draft = preferenceDraft;
                if (draft == null) {
                  savingPreferences = false;
                } else if (observed != null &&
                    _preferenceSignature(observed) ==
                        _preferenceSignature(draft)) {
                  savingPreferences = false;
                  preferenceDraft = null;
                  preferenceMutationError = null;
                  mutationSignature = null;
                  mutationId = null;
                }
              }
            });
          },
          onError: (_) {
            if (_isCurrent(epoch)) {
              setState(
                () => preferenceObservationError =
                    widget.strings.notificationPreferencesError,
              );
            }
          },
        );
  }

  void _observeReadCursor(_PaneEpoch epoch) {
    unawaited(readSubscription?.cancel());
    if (_isCurrent(epoch)) setStateIfMounted(() => cursorError = null);
    readSubscription = _inbox
        .observeReadCursor(
          householdId: epoch.householdId,
          memberId: epoch.memberId,
          memberJoinedAt: epoch.memberJoinedAt!,
        )
        .listen(
          (snapshot) {
            if (!_isCurrent(epoch)) return;
            setState(() {
              readCursor = snapshot;
              cursorError = null;
              if (inboxRetryAction == _InboxRetryAction.observeCursor) {
                inboxRetryAction = null;
              }
            });
            _recomputeUnread();
            _scheduleMarkVisible(epoch);
          },
          onError: (Object error) {
            if (!_isCurrent(epoch)) return;
            setState(() {
              readCursor = const NotificationReadCursorSnapshot(
                cursor: null,
                authority: NotificationCursorAuthority.error,
              );
              cursorError = _notificationErrorMessage(widget.strings, error);
              inboxRetryAction = _InboxRetryAction.observeCursor;
            });
            _recomputeUnread();
          },
        );
  }

  void _observeProvider(_PaneEpoch epoch) {
    unawaited(providerSubscription?.cancel());
    final hash = deviceSnapshot?.installationHash;
    if (hash == null) {
      if (!_isCurrent(epoch)) return;
      setStateIfMounted(
        () => providerSnapshot = const NotificationProviderEvidenceSnapshot(
          evidence:
              NotificationProviderEvidence.notVerifiedForCurrentInstallation,
          authority: NotificationObservationAuthority.error,
          updatedAt: null,
          attemptCount: 0,
        ),
      );
      return;
    }
    if (_isCurrent(epoch)) {
      setStateIfMounted(
        () => providerSnapshot = NotificationProviderEvidenceSnapshot(
          evidence:
              providerSnapshot?.evidence ??
              NotificationProviderEvidence.notVerifiedForCurrentInstallation,
          authority: NotificationObservationAuthority.loading,
          updatedAt: providerSnapshot?.updatedAt,
          attemptCount: providerSnapshot?.attemptCount ?? 0,
        ),
      );
    }
    providerSubscription = ref
        .read(notificationDeliveryEvidenceRepositoryProvider)
        .observe(
          householdId: epoch.householdId,
          memberId: epoch.memberId,
          memberJoinedAt: epoch.memberJoinedAt!,
          installationHash: hash,
        )
        .listen(
          (snapshot) {
            if (_isCurrent(epoch)) {
              setState(() => providerSnapshot = snapshot);
            }
          },
          onError: (_) {
            if (!_isCurrent(epoch)) return;
            setState(
              () => providerSnapshot = NotificationProviderEvidenceSnapshot(
                evidence:
                    providerSnapshot?.evidence ??
                    NotificationProviderEvidence
                        .notVerifiedForCurrentInstallation,
                authority: NotificationObservationAuthority.error,
                updatedAt: providerSnapshot?.updatedAt,
                attemptCount: providerSnapshot?.attemptCount ?? 0,
              ),
            );
          },
        );
  }

  void _observeRecent(_PaneEpoch epoch) {
    unawaited(recentSubscription?.cancel());
    setStateIfMounted(() {
      loadingInbox = true;
      inboxError = null;
    });
    _recomputeUnread(
      epoch: epoch,
      authority: NotificationObservationAuthority.loading,
    );
    recentSubscription = _inbox
        .observeRecent(
          householdId: epoch.householdId,
          memberId: epoch.memberId,
          memberJoinedAt: epoch.memberJoinedAt!,
        )
        .listen(
          (next) {
            if (!_isCurrent(epoch)) return;
            setState(() {
              page = _mergePages(
                page,
                next,
                preserveExisting: page != null,
                preserveContinuation: loadedOlderPage,
              );
              loadingInbox = false;
              if (inboxRetryAction != _InboxRetryAction.loadMore) {
                inboxError = null;
              }
              if (inboxRetryAction == _InboxRetryAction.observeRecent) {
                inboxRetryAction = null;
              }
            });
            _recomputeUnread(epoch: epoch);
            _scheduleMarkVisible(epoch);
          },
          onError: (Object error) {
            if (!_isCurrent(epoch)) return;
            setState(() {
              loadingInbox = false;
              inboxError = _notificationErrorMessage(widget.strings, error);
              inboxRetryAction = _InboxRetryAction.observeRecent;
            });
            _recomputeUnread(
              epoch: epoch,
              authority: NotificationObservationAuthority.error,
            );
          },
        );
  }

  Future<void> _loadMore({NotificationInboxPageCursor? exactAfter}) async {
    final epoch = _epoch;
    final current = page;
    final joinedAt = epoch.memberJoinedAt;
    final after = exactAfter ?? current?.nextCursor;
    if (after == null || current == null || joinedAt == null || loadingMore) {
      return;
    }
    setState(() => loadingMore = true);
    try {
      final next = await _inbox.loadRecent(
        householdId: epoch.householdId,
        memberId: epoch.memberId,
        memberJoinedAt: joinedAt,
        after: after,
      );
      if (!_isCurrent(epoch)) return;
      setState(() {
        page = _mergePages(page ?? current, next, preserveExisting: true);
        loadedOlderPage = true;
        inboxError = null;
        failedPageCursor = null;
        if (inboxRetryAction == _InboxRetryAction.loadMore) {
          inboxRetryAction = null;
        }
      });
      _recomputeUnread(epoch: epoch);
      _scheduleMarkVisible(epoch);
    } on Object catch (error) {
      if (_isCurrent(epoch)) {
        setState(() {
          inboxError = _notificationErrorMessage(widget.strings, error);
          failedPageCursor = after;
          inboxRetryAction = _InboxRetryAction.loadMore;
        });
      }
    } finally {
      if (_isCurrent(epoch)) setState(() => loadingMore = false);
    }
  }

  void _recomputeUnread({
    _PaneEpoch? epoch,
    NotificationObservationAuthority? authority,
  }) {
    if (epoch != null && !_isCurrent(epoch)) return;
    final current = page;
    final visibleItems = [...?current?.items];
    if (pinnedItem case final item?) visibleItems.add(item);
    final next = NotificationUnreadPolicy.hasUnread(
      items: visibleItems,
      droppedItemCount: current?.droppedItemCount ?? 0,
      cursor: readCursor?.cursor,
      cursorAuthority:
          readCursor?.authority ?? NotificationCursorAuthority.unknown,
      pageAuthority:
          authority ??
          current?.authority ??
          NotificationObservationAuthority.loading,
      previousValue: unread,
    );
    _setUnread(next, epoch: epoch ?? _epoch);
  }

  void _setUnread(bool value, {_PaneEpoch? epoch}) {
    if (unread == value) return;
    unread = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (epoch == null || _isCurrent(epoch))) {
        widget.onUnreadChanged(value);
      }
    });
  }

  void _selectSection(NotificationUpdatesSection value) {
    setState(() => section = value);
    if (value == NotificationUpdatesSection.reminders) {
      _scheduleMarkVisible(_epoch);
    } else {
      widget.onChangesSelected();
    }
  }

  void _scheduleMarkVisible(_PaneEpoch epoch) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrent(epoch)) unawaited(_markVisible(epoch: epoch));
    });
  }

  Future<void> _markVisible({
    _PaneEpoch? epoch,
    NotificationReadCursor? exactCursor,
  }) async {
    final activeEpoch = epoch ?? _epoch;
    final joinedAt = activeEpoch.memberJoinedAt;
    final current = page;
    if (!_isCurrent(activeEpoch) ||
        widget.mode != NotificationCenterPaneMode.updates ||
        section != NotificationUpdatesSection.reminders ||
        joinedAt == null ||
        markingRead ||
        current?.authority !=
            NotificationObservationAuthority.serverConfirmed ||
        current?.hasPendingWrites == true ||
        current!.droppedItemCount > 0 ||
        readCursor?.authority != NotificationCursorAuthority.serverConfirmed) {
      return;
    }
    final visibleItems = [...current.items];
    if (pinnedItem case final item?) visibleItems.add(item);
    final NotificationReadCursor cursor;
    if (exactCursor != null) {
      cursor = exactCursor;
    } else {
      final active =
          visibleItems
              .where(
                (item) =>
                    item.status == NotificationInboxStatus.active &&
                    (item == pinnedItem ||
                        current.authorityFor(item) ==
                            NotificationObservationAuthority.serverConfirmed),
              )
              .toList()
            ..sort((left, right) {
              final time = right.createdAt.compareTo(left.createdAt);
              return time != 0 ? time : right.id.compareTo(left.id);
            });
      if (active.isEmpty) return;
      cursor = NotificationReadCursor(
        createdAt: active.first.createdAt,
        intentId: active.first.id,
      );
    }
    final previous = readCursor?.cursor;
    if (readCursor?.authority == NotificationCursorAuthority.serverConfirmed &&
        previous != null &&
        NotificationReadCursor.compare(cursor, previous) <= 0) {
      return;
    }
    markingRead = true;
    try {
      await _inbox.markRead(activeEpoch.householdId, joinedAt, cursor);
      if (_isCurrent(activeEpoch)) {
        setState(() {
          readError = null;
          failedReadCursor = null;
          if (inboxRetryAction == _InboxRetryAction.markRead) {
            inboxRetryAction = null;
          }
        });
      }
    } on Object catch (error) {
      if (_isCurrent(activeEpoch)) {
        setState(() {
          readError = _notificationErrorMessage(widget.strings, error);
          failedReadCursor = cursor;
          inboxRetryAction = _InboxRetryAction.markRead;
        });
      }
    } finally {
      if (_isCurrent(activeEpoch)) markingRead = false;
    }
  }

  Future<void> _restorePendingRoute(_PaneEpoch epoch) async {
    try {
      final route = await _interaction.readPendingRoute();
      if (route == null || !_isCurrent(epoch)) return;
      setState(() => pendingRoute = route);
      await _resolvePendingRoute(epoch: epoch);
    } on Object {
      if (_isCurrent(epoch)) {
        setState(() {
          inboxError = widget.strings.notificationInboxLongError;
          inboxRetryAction = _InboxRetryAction.resolveRoute;
        });
      }
    }
  }

  Future<void> _openItem(NotificationInboxItem item) async {
    final epoch = _epoch;
    final route = await _interaction.persistClick(
      NotificationRoutePayload(
        householdId: item.householdId,
        inboxItemId: item.id,
      ).toJson(),
    );
    if (!_isCurrent(epoch)) {
      await _interaction.clearPendingRouteIfGeneration(route.generation);
      return;
    }
    setState(() => pendingRoute = route);
    await _resolvePendingRoute(epoch: epoch);
  }

  Future<void> _resolvePendingRoute({_PaneEpoch? epoch}) async {
    final activeEpoch = epoch ?? _epoch;
    final route = pendingRoute;
    final joinedAt = activeEpoch.memberJoinedAt;
    if (!_isCurrent(activeEpoch) || route == null || joinedAt == null) return;
    if (route.payload.householdId != activeEpoch.householdId) {
      setState(() => inboxError = widget.strings.notificationInboxUnavailable);
      widget.onRouteRejected();
      await _clearRouteIfCurrent(route, activeEpoch);
      return;
    }
    final resolving = route.copyWith(
      state: NotificationPendingRouteState.resolving,
    );
    final claimed = await _interaction.compareAndSetPendingRoute(
      expected: route,
      next: resolving,
    );
    if (!claimed) return;
    if (!_isCurrent(activeEpoch)) {
      await _interaction.clearPendingRouteIfGeneration(resolving.generation);
      return;
    }
    setState(() => pendingRoute = resolving);
    try {
      final resolution = await _interaction.resolve(route.payload);
      if (!_isCurrent(activeEpoch) ||
          !_sameRouteIdentity(pendingRoute, resolving)) {
        return;
      }
      if (resolution.disposition == NotificationRouteDisposition.reject) {
        setState(
          () => inboxError = widget.strings.notificationInboxUnavailable,
        );
        widget.onRouteRejected();
        await _clearRouteIfCurrent(resolving, activeEpoch);
        return;
      }
      final item = await _inbox.loadByIDFromServer(
        householdId: activeEpoch.householdId,
        memberId: activeEpoch.memberId,
        memberJoinedAt: joinedAt,
        inboxItemId: route.payload.inboxItemId,
      );
      if (!_isCurrent(activeEpoch) ||
          !_sameRouteIdentity(pendingRoute, resolving)) {
        return;
      }
      setState(() {
        pinnedItem = item;
        section = NotificationUpdatesSection.reminders;
        inboxError = null;
      });
      widget.onRouteOpened();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!_isCurrent(activeEpoch) ||
            !_sameRouteIdentity(pendingRoute, resolving)) {
          return;
        }
        if (await _clearRouteIfCurrent(resolving, activeEpoch)) {
          _scheduleMarkVisible(activeEpoch);
        }
      });
    } on Object {
      final retryable = resolving.copyWith(
        state: NotificationPendingRouteState.retryable,
      );
      final updated = await _interaction.compareAndSetPendingRoute(
        expected: resolving,
        next: retryable,
      );
      if (updated && _isCurrent(activeEpoch)) {
        setState(() {
          pendingRoute = retryable;
          inboxError = widget.strings.notificationInboxLongError;
          inboxRetryAction = _InboxRetryAction.resolveRoute;
        });
      }
    }
  }

  Future<bool> _clearRouteIfCurrent(
    NotificationPendingRoute route,
    _PaneEpoch epoch,
  ) async {
    if (!_isCurrent(epoch) || !_sameRouteIdentity(pendingRoute, route)) {
      return false;
    }
    final cleared = await _interaction.clearPendingRouteIfGeneration(
      route.generation,
    );
    if (!_isCurrent(epoch) ||
        !cleared ||
        !_sameRouteIdentity(pendingRoute, route)) {
      return false;
    }
    setState(() => pendingRoute = null);
    return true;
  }

  HouseholdNotificationPreferences? get _effectivePreferences {
    if (preferenceObservationError != null) return null;
    if (preferenceDraft case final draft?) return draft;
    final observed = preferenceSnapshot?.preferences;
    if (observed != null) return observed;
    if (preferenceSnapshot?.authority !=
        NotificationPreferenceAuthority.missingDefaults) {
      return null;
    }
    final joinedAt = widget.memberJoinedAt;
    final timeZone = widget.timeZoneIdentifier;
    if (joinedAt == null || timeZone == null || timeZone.isEmpty) return null;
    return HouseholdNotificationPreferences.conservative(
      uid: widget.memberId,
      householdId: widget.householdId,
      memberJoinedAt: joinedAt,
      timeZoneIdentifier: timeZone,
    );
  }

  Future<void> _changePreference(
    NotificationPreferenceField field,
    bool value,
  ) async {
    final epoch = _epoch;
    final current = _effectivePreferences;
    if (current == null || savingPreferences) return;
    final next = switch (field) {
      NotificationPreferenceField.medication => current.copyWith(
        medicationRemindersEnabled: value,
      ),
      NotificationPreferenceField.assignment => current.copyWith(
        assignmentAlertsEnabled: value,
      ),
      NotificationPreferenceField.urgent => current.copyWith(
        urgentAlertsEnabled: value,
      ),
      NotificationPreferenceField.push => current.copyWith(pushEnabled: value),
      NotificationPreferenceField.quietHours => current.copyWith(
        quietHoursEnabled: value,
      ),
      NotificationPreferenceField.summary => current.copyWith(
        summaryEnabled: value,
      ),
    };
    await _savePreferences(next, epoch);
  }

  Future<void> _changeBackups(Set<String> memberIds) async {
    final epoch = _epoch;
    final current = _effectivePreferences;
    if (current == null || savingPreferences) return;
    final sorted = memberIds.toList(growable: false)..sort();
    await _savePreferences(current.copyWith(backupForMemberIds: sorted), epoch);
  }

  Future<void> _savePreferences(
    HouseholdNotificationPreferences next,
    _PaneEpoch epoch,
  ) async {
    if (!_isCurrent(epoch)) return;
    final signature = _preferenceSignature(next);
    if (signature != mutationSignature) {
      mutationSignature = signature;
      mutationId = _newMutationId('preferences');
    }
    setState(() {
      preferenceDraft = next;
      savingPreferences = true;
      preferenceMutationError = null;
    });
    try {
      await _preferences.save(next, clientMutationId: mutationId!);
    } on Object catch (error) {
      if (_isCurrent(epoch)) {
        setState(() {
          savingPreferences = false;
          preferenceMutationError = _preferenceErrorMessage(
            widget.strings,
            error,
          );
        });
      }
    }
  }

  Future<void> _repairPreferences() async {
    final epoch = _epoch;
    if (!_isCurrent(epoch)) return;
    repairMutationId ??= _newMutationId('repair');
    setState(() {
      savingPreferences = true;
      preferenceMutationError = null;
    });
    try {
      await _preferences.resetMalformed(
        householdId: epoch.householdId,
        clientMutationId: repairMutationId!,
      );
      if (_isCurrent(epoch)) repairMutationId = null;
    } on Object catch (error) {
      if (_isCurrent(epoch)) {
        setState(() {
          savingPreferences = false;
          preferenceMutationError = _preferenceErrorMessage(
            widget.strings,
            error,
          );
        });
      }
    }
  }

  NotificationCapability get _capability {
    final device = deviceSnapshot;
    final provider = providerSnapshot;
    return NotificationCapability(
      osPermission: device?.osPermission ?? NotificationOsPermission.error,
      preferenceAuthority: preferenceObservationError != null
          ? NotificationPreferenceAuthority.error
          : preferenceSnapshot?.authority ??
                NotificationPreferenceAuthority.missingDefaults,
      installationReadiness:
          device?.installationReadiness ??
          NotificationInstallationReadiness.error,
      providerEvidence:
          provider?.evidence ??
          NotificationProviderEvidence.notVerifiedForCurrentInstallation,
      providerAuthority:
          provider?.authority ?? NotificationObservationAuthority.loading,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(notificationPendingRouteSignalProvider, (previous, next) {
      if (previous != next) unawaited(_restorePendingRoute(_epoch));
    });
    if (widget.mode == NotificationCenterPaneMode.hidden) {
      return const SizedBox.shrink();
    }
    if (widget.mode == NotificationCenterPaneMode.profile) {
      return NotificationProfileCard(
        strings: widget.strings,
        capability: _capability,
        providerSnapshot: providerSnapshot,
        preferences: _effectivePreferences,
        memberNamesById: {
          for (final member in widget.members)
            if (member.id != widget.memberId) member.id: member.displayName,
        },
        saving: savingPreferences,
        mutationError: preferenceMutationError,
        onEnablePermission: () => unawaited(_configureDevice(request: true)),
        onOpenSettings: () =>
            unawaited(ref.read(notificationRepositoryProvider).openSettings()),
        onRetryDevice: () => unawaited(_configureDevice()),
        onRepairPreferences: () => unawaited(_repairPreferences()),
        onRetryPreferences: () => _observePreferences(_epoch),
        onRetryPreferenceSave: () {
          final draft = preferenceDraft;
          if (draft != null) {
            unawaited(_savePreferences(draft, _epoch));
          } else if (repairMutationId != null) {
            unawaited(_repairPreferences());
          }
        },
        onPreferenceChanged: (field, value) =>
            unawaited(_changePreference(field, value)),
        onBackupChanged: (ids) => unawaited(_changeBackups(ids)),
        onMinuteChanged: (field, minute) {
          final current = _effectivePreferences;
          if (current == null) return;
          final next = switch (field) {
            NotificationPreferenceMinuteField.quietStart => current.copyWith(
              quietStartMinute: minute,
            ),
            NotificationPreferenceMinuteField.quietEnd => current.copyWith(
              quietEndMinute: minute,
            ),
            NotificationPreferenceMinuteField.summary => current.copyWith(
              summaryMinute: minute,
            ),
          };
          unawaited(_savePreferences(next, _epoch));
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NotificationUpdatesSwitcher(
          strings: widget.strings,
          selection: section,
          changesUnread: widget.changesUnread,
          remindersUnread: unread,
          onChanged: _selectSection,
        ),
        const SizedBox(height: 14),
        if (section == NotificationUpdatesSection.changes)
          widget.changes
        else
          NotificationInboxCard(
            strings: widget.strings,
            page: page,
            pinnedItem: pinnedItem,
            loading: loadingInbox,
            loadingMore: loadingMore,
            errorMessage: readError ?? cursorError ?? inboxError,
            onRetry: () {
              switch (inboxRetryAction) {
                case _InboxRetryAction.markRead:
                  final cursor = failedReadCursor;
                  setState(() => readError = null);
                  unawaited(_markVisible(epoch: _epoch, exactCursor: cursor));
                case _InboxRetryAction.observeCursor:
                  _observeReadCursor(_epoch);
                case _InboxRetryAction.loadMore:
                  unawaited(_loadMore(exactAfter: failedPageCursor));
                case _InboxRetryAction.resolveRoute:
                  unawaited(_resolvePendingRoute(epoch: _epoch));
                case _InboxRetryAction.observeRecent:
                case null:
                  if (_epoch.memberJoinedAt != null) _observeRecent(_epoch);
              }
            },
            onLoadMore: () => unawaited(_loadMore()),
            onOpenItem: (item) => unawaited(_openItem(item)),
          ),
      ],
    );
  }

  @override
  void dispose() {
    unawaited(readSubscription?.cancel());
    unawaited(recentSubscription?.cancel());
    unawaited(preferenceSubscription?.cancel());
    unawaited(providerSubscription?.cancel());
    super.dispose();
  }

  void setStateIfMounted(VoidCallback action) {
    if (mounted) setState(action);
  }

  bool _isCurrent(_PaneEpoch epoch) =>
      mounted && epoch.generation == _epoch.generation;
}

final class _PaneEpoch {
  const _PaneEpoch({
    required this.generation,
    required this.householdId,
    required this.memberId,
    required this.memberJoinedAt,
    required this.timeZoneIdentifier,
  });

  final int generation;
  final String householdId;
  final String memberId;
  final DateTime? memberJoinedAt;
  final String? timeZoneIdentifier;
}

bool _sameRouteIdentity(
  NotificationPendingRoute? left,
  NotificationPendingRoute right,
) =>
    left?.generation == right.generation &&
    left?.state == right.state &&
    left?.payload.householdId == right.payload.householdId &&
    left?.payload.inboxItemId == right.payload.inboxItemId;

NotificationInboxPage _mergePages(
  NotificationInboxPage? current,
  NotificationInboxPage next, {
  required bool preserveExisting,
  bool preserveContinuation = false,
}) {
  final byId = <String, NotificationInboxItem>{
    if (preserveExisting)
      for (final item in current?.items ?? const <NotificationInboxItem>[])
        item.id: item,
    for (final item in next.items) item.id: item,
  };
  final items = byId.values.toList(growable: false)
    ..sort((left, right) {
      final time = right.createdAt.compareTo(left.createdAt);
      return time != 0 ? time : right.id.compareTo(left.id);
    });
  return NotificationInboxPage(
    items: List.unmodifiable(items),
    droppedItemCount:
        (preserveExisting ? current?.droppedItemCount ?? 0 : 0) +
        next.droppedItemCount,
    authority: next.authority,
    hasPendingWrites: next.hasPendingWrites,
    mayHaveMore: preserveContinuation
        ? current?.mayHaveMore ?? next.mayHaveMore
        : next.mayHaveMore,
    nextCursor: preserveContinuation
        ? current?.nextCursor ?? next.nextCursor
        : next.nextCursor,
    itemAuthorities: {
      if (preserveExisting && current != null)
        for (final item in current.items) item.id: current.authorityFor(item),
      for (final item in next.items) item.id: next.authorityFor(item),
    },
  );
}

String _notificationErrorMessage(AppStrings strings, Object error) {
  if (error is NotificationCenterException) {
    return switch (error.code) {
      NotificationCenterErrorCode.permission =>
        strings.notificationPermissionError,
      NotificationCenterErrorCode.network => strings.notificationNetworkError,
      NotificationCenterErrorCode.backendUnavailable =>
        strings.notificationBackendError,
      NotificationCenterErrorCode.invalidInput ||
      NotificationCenterErrorCode.stale ||
      NotificationCenterErrorCode.malformed => strings.notificationDataError,
    };
  }
  return strings.notificationInboxLongError;
}

String _preferenceErrorMessage(AppStrings strings, Object error) {
  if (error is NotificationCenterException) {
    return switch (error.code) {
      NotificationCenterErrorCode.permission =>
        strings.notificationPreferencesPermissionError,
      NotificationCenterErrorCode.network =>
        strings.notificationPreferencesNetworkError,
      NotificationCenterErrorCode.backendUnavailable =>
        strings.notificationPreferencesBackendError,
      NotificationCenterErrorCode.invalidInput ||
      NotificationCenterErrorCode.stale ||
      NotificationCenterErrorCode.malformed =>
        strings.notificationPreferencesDataError,
    };
  }
  return strings.notificationPreferencesError;
}

String _preferenceSignature(HouseholdNotificationPreferences value) => [
  value.medicationRemindersEnabled,
  value.assignmentAlertsEnabled,
  value.urgentAlertsEnabled,
  value.pushEnabled,
  value.backupForMemberIds.join(','),
  value.quietHoursEnabled,
  value.quietStartMinute,
  value.quietEndMinute,
  value.summaryEnabled,
  value.summaryMinute,
].join('|');

String _newMutationId(String action) =>
    'flutter-notification-$action-'
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
