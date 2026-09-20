import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/ai_plan.dart';
import '../models/models.dart';

/// Parses natural-language pet-care instructions into structured tasks using
/// Firebase AI Logic (Gemini Developer API).
class AiService {
  AiService._();
  static final AiService instance = AiService._();

  /// Pinned instead of using a moving `-latest` alias so a released build does
  /// not silently switch model behavior. Keep this aligned with Firebase AI
  /// Logic's supported-model list.
  static const String modelName = 'gemini-3.8-flash';

  /// Longest instruction accepted. Anything past this is the user pasting a
  /// document, which costs tokens without improving the parse.
  static const int maxInstructionLength = 1000;

  Future<AiParseResult> parseInstruction(String text, List<Pet> pets) async {
    if (Firebase.apps.isEmpty) {
      throw const AiFailure(
        AiFailureKind.configuration,
        'Firebase was not initialized before an AI request.',
      );
    }

    final instruction = text.length > maxInstructionLength
        ? text.substring(0, maxInstructionLength)
        : text;
    try {
      final googleAI = FirebaseAI.googleAI();
      final model = googleAI.generativeModel(
        model: modelName,
        systemInstruction: Content.text(_systemPrompt()),
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: _schema,
          // A parsed care plan is small. Capping output bounds the cost of a
          // single call and of a prompt that tries to make the model ramble.
          maxOutputTokens: 2048,
        ),
      );

      final petContext = pets.isEmpty
          ? '(no existing pets)'
          : pets
                .map((p) => '- ${p.name} (type: ${p.type.rawValue})')
                .join('\n');

      final response = await model.generateContent([
        Content.text(
          'Existing pets:\n$petContext\n\nUser instruction:\n$instruction',
        ),
      ]);

      final raw = (response.text ?? '').trim();
      if (raw.isEmpty) {
        throw const FormatException('AI returned an empty response.');
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('AI returned a non-object response.');
      }
      try {
        return AiParseResult.fromJson(decoded);
      } catch (error) {
        throw AiFailure(AiFailureKind.invalidResponse, error.toString());
      }
    } catch (error) {
      if (error is AiFailure) rethrow;
      throw classifyFailure(error);
    }
  }

  /// Converts SDK and transport errors into stable product-facing categories.
  /// The original diagnostic remains available for logs, while the UI decides
  /// what is safe and useful to show to a pet owner.
  static AiFailure classifyFailure(Object error) {
    if (error is AiFailure) return error;
    if (error is InvalidApiKey || error is ServiceApiNotEnabled) {
      return AiFailure(AiFailureKind.configuration, error.toString());
    }
    if (error is UnsupportedUserLocation) {
      return AiFailure(AiFailureKind.unsupportedRegion, error.toString());
    }
    if (error is QuotaExceeded) {
      return AiFailure(AiFailureKind.quota, error.toString());
    }
    if (error is TimeoutException) {
      return AiFailure(AiFailureKind.network, error.toString());
    }
    if (error is FormatException) {
      return AiFailure(AiFailureKind.invalidResponse, error.toString());
    }
    if (error is FirebaseException) {
      final details = '${error.code} ${error.message ?? ''}'.toLowerCase();
      if (details.contains('network')) {
        return AiFailure(AiFailureKind.network, error.toString());
      }
      if (details.contains('firebaseappcheck.googleapis.com') &&
          (details.contains('service_disabled') ||
              details.contains('not enabled'))) {
        return AiFailure(AiFailureKind.configuration, error.toString());
      }
      if (details.contains('permission') ||
          details.contains('unauth') ||
          details.contains('app-check') ||
          details.contains('app check')) {
        return AiFailure(AiFailureKind.authorization, error.toString());
      }
      return AiFailure(AiFailureKind.server, error.toString());
    }
    if (error is FirebaseAIException) {
      final message = error.message.toLowerCase();
      if (message.contains('permission_denied') ||
          message.contains('permission denied') ||
          message.contains('unauthenticated') ||
          message.contains('app check') ||
          message.contains('appcheck')) {
        return AiFailure(AiFailureKind.authorization, error.toString());
      }
      if (message.contains('network') ||
          message.contains('connection') ||
          message.contains('timed out')) {
        return AiFailure(AiFailureKind.network, error.toString());
      }
      return AiFailure(AiFailureKind.server, error.toString());
    }
    return AiFailure(AiFailureKind.server, error.toString());
  }

  String _systemPrompt() {
    final categories = CareCategory.builtIns.map((c) => c.id).toList();
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
            'weekdays': Schema.array(items: Schema.integer(), nullable: true),
            'hour': Schema.integer(),
            'minute': Schema.integer(),
            'date': Schema.string(nullable: true),
          },
        ),
      ),
      'petWeights': Schema.array(
        items: Schema.object(
          properties: {'petName': Schema.string(), 'weightKg': Schema.number()},
        ),
        nullable: true,
      ),
    },
  );
}

enum AiFailureKind {
  configuration,
  network,
  authorization,
  quota,
  unsupportedRegion,
  invalidResponse,
  server,
}

class AiFailure implements Exception {
  const AiFailure(this.kind, this.diagnostic);

  final AiFailureKind kind;
  final String diagnostic;

  @override
  String toString() => 'AiFailure($kind): $diagnostic';
}
