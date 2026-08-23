import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';

import '../models/ai_plan.dart';
import '../models/models.dart';

/// Parses natural-language pet-care instructions into structured tasks using
/// Firebase AI Logic (Gemini Developer API).
class AiService {
  AiService._();
  static final AiService instance = AiService._();

  Future<AiParseResult> parseInstruction(String text, List<Pet> pets) async {
    final googleAI = FirebaseAI.googleAI();
    final model = googleAI.generativeModel(
      model: 'gemini-flash-latest',
      systemInstruction: Content.text(_systemPrompt()),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: _schema,
      ),
    );

    final petContext = pets.isEmpty
        ? '(no existing pets)'
        : pets.map((p) => '- ${p.name} (type: ${p.type.rawValue})').join('\n');

    final response = await model.generateContent([
      Content.text('Existing pets:\n$petContext\n\nUser instruction:\n$text'),
    ]);

    final raw = (response.text ?? '').trim();
    if (raw.isEmpty) {
      throw const FormatException('AI 没有返回内容，请重试。');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI 返回格式异常，请重试。');
    }
    return AiParseResult.fromJson(decoded);
  }

  String _systemPrompt() {
    final categories =
        CareCategory.builtIns.map((c) => c.id).toList();
    return '''
You are a pet-care scheduling assistant. Parse the user's instruction and extract concrete care tasks for their pets.

Rules:
- Each task is either a recurring routine or a one-off event.
- Map each task to exactly one category id from: ${categories.join(', ')}.
- "kind" is "routine" for recurring things, "oneOff" for one-time events.
- "frequency" is one of: daily, selectedDays, intervalDays, intervalWeeks, intervalMonths, nthWeekday, intervalYears.
- Use 24-hour time for "hour" (0-23) and "minute" (0-59). Pick a sensible default when the text is vague (e.g. "after dinner" -> around 21:00).
- "interval" is the N in "every N days/weeks/months/years". For nthWeekday, "interval" is the week number: 1=first, 2=second, 3=third, 4=fourth, 5=last week of the month.
- "weekdays" uses 1=Sunday .. 7=Saturday. For selectedDays list the days. For nthWeekday put exactly one weekday.
- "petName" should match the pet mentioned (e.g. "Lisa", "聪聪"). Leave null when it applies to all pets.
- "3 meals a day" becomes separate tasks (one per meal time).
- Weight ("体重 ... 公斤") goes into "petWeights" (petName + weightKg), NOT into tasks.
- "上一次是 X 月" (last time was X months ago) means start counting from that month — set a reasonable "date" or just the interval/frequency; do not overthink, keep the recurrence.
- Return ONLY valid JSON matching the schema. No markdown, no commentary.
''';
  }

  static final Schema _schema = Schema.object(
    properties: {
      'tasks': Schema.array(
        items: Schema.object(
          properties: {
            'title': Schema.string(),
            'category': Schema.enumString(
              enumValues: CareCategory.builtIns.map((c) => c.id).toList(),
            ),
            'petName': Schema.string(nullable: true),
            'kind': Schema.enumString(enumValues: ['routine', 'oneOff']),
            'frequency': Schema.enumString(
              enumValues: [
                'daily',
                'selectedDays',
                'intervalDays',
                'intervalWeeks',
                'intervalMonths',
                'nthWeekday',
                'intervalYears',
              ],
            ),
            'interval': Schema.integer(nullable: true),
            'weekdays': Schema.array(
              items: Schema.integer(),
              nullable: true,
            ),
            'hour': Schema.integer(),
            'minute': Schema.integer(),
            'date': Schema.string(nullable: true),
          },
        ),
      ),
      'petWeights': Schema.array(
        items: Schema.object(
          properties: {
            'petName': Schema.string(),
            'weightKg': Schema.number(),
          },
        ),
        nullable: true,
      ),
    },
  );
}
