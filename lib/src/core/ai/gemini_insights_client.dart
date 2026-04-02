import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'finance_numeric_snapshot.dart';

/// Google Gemini for short coaching copy only. [FinanceNumericSnapshot] must stay PII-free.
class GeminiInsightsClient {
  GeminiInsightsClient._();

  /// Only models whose **Standard** pricing row shows **Free of charge** for both
  /// input and output on the **Free** tier (not "Not available").
  /// https://ai.google.dev/gemini-api/docs/pricing
  ///
  /// Excludes paid-only models (e.g. Gemini 3.1 Pro Preview, image/TTS variants) and Batch-only rows.
  /// Order: lighter / newer free-tier options first; versioned IDs as fallbacks.
  static const _modelsToTry = [
    'gemini-3.1-flash-lite-preview',
    'gemini-3-flash-preview',
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
    'gemini-2.0-flash-lite',
    'gemini-2.0-flash-lite-001',
    'gemini-2.0-flash',
    'gemini-2.0-flash-001',
  ];

  /// Numeric JSON-only prompts rarely need strict blocking; use block-only-high to cut false finishes.
  static final List<SafetySetting> _relaxedSafety = [
    SafetySetting(HarmCategory.harassment, HarmBlockThreshold.high),
    SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.high),
    SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.high),
    SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.high),
  ];

  static final GenerationConfig _generationConfig = GenerationConfig(
    maxOutputTokens: 512,
    temperature: 0.7,
  );

  static String? get _apiKeyFromEnv =>
      dotenv.env['GEMINI_API_KEY']?.trim().isNotEmpty == true
          ? dotenv.env['GEMINI_API_KEY']!.trim()
          : null;

  /// Optional compile-time override: `--dart-define=GEMINI_API_KEY=...`
  static const String _apiKeyFromDefine = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static String? get apiKey =>
      _apiKeyFromEnv ??
      (_apiKeyFromDefine.trim().isNotEmpty ? _apiKeyFromDefine.trim() : null);

  static bool get isConfigured => apiKey != null;

  static String _systemPrompt() =>
      'You are a careful financial wellness assistant. You only see one JSON object '
      'of numbers and codes. Never ask for names, banks, employers, or account identifiers. '
      'Never state or guess the user\'s country beyond the currency code field. '
      'Do not give legal, tax, or investment advice. '
      'Write exactly 3 short lines (each under 100 characters), plain text, no markdown, '
      'friendly and non-judgmental. '
      'Interpret: h=health 0-100, p=personality code 0-4 (0 planner,1 balanced,2 flexible spender,'
      '3 paydown focus,4 early data), dbm=debt user owes others, dtm=owed to user, '
      'sts=estimated cushion after planned outflows, cap_x=1 means workspace cap exceeded.';

  /// Returns 2–4 plain-text lines, or null if disabled / error.
  static Future<String?> generateCoachNarrative(
    FinanceNumericSnapshot snapshot,
  ) async {
    final key = apiKey;
    if (key == null) return null;

    final userPayload = snapshot.toJsonString();
    final system = _systemPrompt();

    for (final modelId in _modelsToTry) {
      final withSystem = await _tryModel(
        modelId: modelId,
        apiKey: key,
        snapshotLabel: userPayload,
        systemInstruction: Content.system(system),
        combinedUserOnly: null,
      );
      if (withSystem != null) return withSystem;

      final combined = '$system\n\n---\nJSON (no PII):\n$userPayload';
      final userOnly = await _tryModel(
        modelId: modelId,
        apiKey: key,
        snapshotLabel: userPayload,
        systemInstruction: null,
        combinedUserOnly: combined,
      );
      if (userOnly != null) return userOnly;
    }

    if (kDebugMode) {
      debugPrint(
        'GeminiInsightsClient: all models failed for coach narrative. '
        'Check key, network, region support, and model availability in Google AI Studio.',
      );
    }
    return null;
  }

  static Future<String?> _tryModel({
    required String modelId,
    required String apiKey,
    required String snapshotLabel,
    required Content? systemInstruction,
    required String? combinedUserOnly,
  }) async {
    try {
      final model = GenerativeModel(
        model: modelId,
        apiKey: apiKey,
        systemInstruction: systemInstruction,
        safetySettings: _relaxedSafety,
        generationConfig: _generationConfig,
      );

      final content = combinedUserOnly != null
          ? Content.text(combinedUserOnly)
          : Content.text(snapshotLabel);

      final response = await model.generateContent([content]);
      final text = _readResponseText(response);
      if (text != null && text.isNotEmpty) return text;
    } on GenerativeAIException catch (e, st) {
      if (kDebugMode) {
        debugPrint('GeminiInsightsClient ($modelId): $e');
        debugPrint('$st');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('GeminiInsightsClient ($modelId): $e');
        debugPrint('$st');
      }
    }
    return null;
  }

  static String? _readResponseText(GenerateContentResponse response) {
    try {
      final t = response.text;
      if (t != null && t.trim().isNotEmpty) return t.trim();
    } on GenerativeAIException catch (_) {
      // Prompt/candidate blocked — try manual part scan below.
    }

    for (final c in response.candidates) {
      final parts = c.content.parts.whereType<TextPart>();
      if (parts.isEmpty) continue;
      final buffer = StringBuffer();
      for (final p in parts) {
        buffer.write(p.text);
      }
      final s = buffer.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }
}
