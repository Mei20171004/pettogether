import 'models.dart';

/// A single care task parsed from a natural-language instruction.
class AiParsedTask {
  const AiParsedTask({
    required this.title,
    required this.category,
    required this.kind,
    required this.frequency,
    required this.hour,
    required this.minute,
    this.petName,
    this.interval = 1,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.date,
  });

  final String title;
  final CareCategory category;
  final CareTaskKind kind;
  final CareRoutineFrequency frequency;
  final int hour;
  final int minute;
  final String? petName;
  final int interval;
  final List<int> weekdays;
  final DateTime? date;

  factory AiParsedTask.fromJson(Map<String, dynamic> json) => AiParsedTask(
        title: json['title'] as String,
        category: CareCategory.fromRaw(json['category'] as String),
        kind: json['kind'] == 'oneOff'
            ? CareTaskKind.oneOff
            : CareTaskKind.routine,
        frequency:
            CareRoutineFrequency.fromRaw(json['frequency'] as String? ?? 'daily'),
        hour: (json['hour'] as num?)?.toInt() ?? 9,
        minute: (json['minute'] as num?)?.toInt() ?? 0,
        petName: json['petName'] as String?,
        interval: (json['interval'] as num?)?.toInt() ?? 1,
        weekdays: (json['weekdays'] as List?)
                ?.whereType<num>()
                .map((e) => e.toInt())
                .toList() ??
            const [1, 2, 3, 4, 5, 6, 7],
        date: json['date'] == null
            ? null
            : DateTime.tryParse(json['date'] as String),
      );
}

/// A pet weight update parsed from the instruction.
class AiParsedPetWeight {
  const AiParsedPetWeight({required this.petName, required this.weightKg});

  final String petName;
  final double weightKg;

  factory AiParsedPetWeight.fromJson(Map<String, dynamic> json) =>
      AiParsedPetWeight(
        petName: json['petName'] as String,
        weightKg: (json['weightKg'] as num).toDouble(),
      );
}

/// The full parsed result of an AI instruction.
class AiParseResult {
  const AiParseResult({required this.tasks, required this.petWeights});

  final List<AiParsedTask> tasks;
  final List<AiParsedPetWeight> petWeights;

  factory AiParseResult.fromJson(Map<String, dynamic> json) => AiParseResult(
        tasks: (json['tasks'] as List? ?? [])
            .map((e) => AiParsedTask.fromJson(e as Map<String, dynamic>))
            .toList(),
        petWeights: (json['petWeights'] as List? ?? [])
            .map((e) => AiParsedPetWeight.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
