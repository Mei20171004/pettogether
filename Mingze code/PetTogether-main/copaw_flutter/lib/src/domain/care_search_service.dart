import 'package:timezone/timezone.dart' as tz;

import 'health_models.dart';
import 'medication_models.dart';
import 'models.dart';
import 'plus_features.dart';

/// Which kind of record a search result came from.
enum CareSearchKind { health, medication, task }

/// A search over the household's full recorded history.
///
/// Part of [PlusFeature.longTermSearch]. Every filter is optional; an empty
/// query returns the whole history in reverse chronological order.
final class CareSearchQuery {
  const CareSearchQuery({
    this.petId,
    this.fromLocalDate,
    this.toLocalDate,
    this.kinds = const {
      CareSearchKind.health,
      CareSearchKind.medication,
      CareSearchKind.task,
    },
    this.text = '',
  });

  /// Restricts results to one pet. `null` searches every pet.
  final String? petId;

  /// Inclusive household-local bounds, formatted `yyyy-MM-dd`.
  final String? fromLocalDate;
  final String? toLocalDate;

  final Set<CareSearchKind> kinds;

  /// Case-insensitive substring match over the text a record actually stores.
  final String text;

  bool get isEmpty =>
      petId == null &&
      fromLocalDate == null &&
      toLocalDate == null &&
      text.trim().isEmpty &&
      kinds.length == CareSearchKind.values.length;
}

/// One result row. Every field is copied from the source record; nothing here
/// is derived, inferred, or summarized.
final class CareSearchResult {
  const CareSearchResult({
    required this.kind,
    required this.id,
    required this.occurredAt,
    required this.localDate,
    required this.petId,
    required this.petName,
    required this.title,
    required this.detail,
    required this.isServerConfirmed,
  });

  final CareSearchKind kind;
  final String id;

  /// The instant this row is ordered by.
  final DateTime occurredAt;

  /// The household-local day this row belongs to.
  final String localDate;

  final String petId;
  final String petName;

  /// The record's own title text.
  final String title;

  /// The record's own free text, when it stored any.
  final String? detail;

  /// False while a local write has not been confirmed by the server. The row is
  /// still shown, because hiding it would misrepresent what the caregiver did,
  /// but it must never be presented as an established fact.
  final bool isServerConfirmed;
}

/// A day of results, newest day first.
final class CareSearchDay {
  const CareSearchDay({required this.localDate, required this.results});

  final String localDate;
  final List<CareSearchResult> results;
}

final class CareSearchOutcome {
  const CareSearchOutcome({
    required this.days,
    required this.totalCount,
    required this.undatedCount,
  });

  final List<CareSearchDay> days;
  final int totalCount;

  /// Records whose household-local day could not be determined, so they are
  /// reported separately instead of being placed on a guessed date.
  final int undatedCount;
}

final class CareSearchService {
  const CareSearchService();

  CareSearchOutcome search({
    required CareSearchQuery query,
    required String timeZoneIdentifier,
    List<HealthRecord> healthRecords = const [],
    List<MedicationOccurrence> medicationOccurrences = const [],
    List<CareTask> tasks = const [],
  }) {
    final location = _location(timeZoneIdentifier);
    final needle = query.text.trim().toLowerCase();
    final matches = <CareSearchResult>[];
    var undated = 0;

    if (query.kinds.contains(CareSearchKind.health)) {
      for (final record in healthRecords) {
        final localDate =
            record.recordedLocalDate ?? _localDate(record.recordedAt, location);
        if (localDate == null) {
          if (_petMatches(query, record.petId)) undated += 1;
          continue;
        }
        final result = CareSearchResult(
          kind: CareSearchKind.health,
          id: record.id,
          occurredAt: record.recordedAt,
          localDate: localDate,
          petId: record.petId,
          petName: record.petNameSnapshot,
          title: record.type.name,
          detail: record.detail,
          isServerConfirmed: true,
        );
        if (_matches(query, result, needle, [record.detail])) {
          matches.add(result);
        }
      }
    }

    if (query.kinds.contains(CareSearchKind.medication)) {
      for (final occurrence in medicationOccurrences) {
        final result = CareSearchResult(
          kind: CareSearchKind.medication,
          id: occurrence.id,
          occurredAt: occurrence.outcomeAt ?? occurrence.dueAt,
          localDate: occurrence.localDate,
          petId: occurrence.petId,
          petName: occurrence.petNameSnapshot,
          title: occurrence.medicationNameSnapshot,
          detail: occurrence.doseText,
          isServerConfirmed: occurrence.isServerConfirmed,
        );
        if (_matches(query, result, needle, [
          occurrence.doseText,
          occurrence.instructions,
          occurrence.skippedReasonNote,
        ])) {
          matches.add(result);
        }
      }
    }

    if (query.kinds.contains(CareSearchKind.task)) {
      for (final task in tasks) {
        final occurredAt = task.completedAt ?? task.dueTime;
        final localDate = _localDate(occurredAt, location);
        if (localDate == null) {
          if (_petMatches(query, task.petId)) undated += 1;
          continue;
        }
        final result = CareSearchResult(
          kind: CareSearchKind.task,
          id: task.id,
          occurredAt: occurredAt,
          localDate: localDate,
          petId: task.petId,
          petName: task.petNameSnapshot ?? '',
          title: task.title,
          detail: null,
          isServerConfirmed: true,
        );
        if (_matches(query, result, needle, const [])) matches.add(result);
      }
    }

    matches.sort((left, right) {
      final byInstant = right.occurredAt.compareTo(left.occurredAt);
      return byInstant != 0 ? byInstant : left.id.compareTo(right.id);
    });

    final grouped = <String, List<CareSearchResult>>{};
    for (final match in matches) {
      grouped.putIfAbsent(match.localDate, () => <CareSearchResult>[]).add(match);
    }
    final days = grouped.keys.toList()..sort((left, right) => right.compareTo(left));

    return CareSearchOutcome(
      days: [
        for (final day in days)
          CareSearchDay(localDate: day, results: grouped[day]!),
      ],
      totalCount: matches.length,
      undatedCount: undated,
    );
  }

  bool _matches(
    CareSearchQuery query,
    CareSearchResult result,
    String needle,
    List<String?> extraText,
  ) {
    if (!_petMatches(query, result.petId)) return false;
    final from = query.fromLocalDate;
    final to = query.toLocalDate;
    if (from != null && result.localDate.compareTo(from) < 0) return false;
    if (to != null && result.localDate.compareTo(to) > 0) return false;
    if (needle.isEmpty) return true;
    final haystack = <String?>[result.title, result.detail, ...extraText];
    return haystack.any(
      (value) => value != null && value.toLowerCase().contains(needle),
    );
  }

  bool _petMatches(CareSearchQuery query, String petId) =>
      query.petId == null || query.petId == petId;

  tz.Location? _location(String identifier) {
    try {
      return tz.getLocation(identifier);
    } on Object {
      return null;
    }
  }

  String? _localDate(DateTime instant, tz.Location? location) {
    if (location == null) return null;
    final local = tz.TZDateTime.from(instant, location);
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}
