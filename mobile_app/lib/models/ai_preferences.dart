import 'app_language.dart';

class AiPreferences {
  const AiPreferences({
    this.model = AiModel.gemini36Flash,
    this.transcriptionLanguage = AppLanguage.automatic,
    this.outputLanguage = AppLanguage.italian,
    this.customPrompt = '',
  });

  final AiModel model;
  final AppLanguage transcriptionLanguage;
  final AppLanguage outputLanguage;
  final String customPrompt;

  AiPreferences copyWith({
    AiModel? model,
    AppLanguage? transcriptionLanguage,
    AppLanguage? outputLanguage,
    String? customPrompt,
  }) {
    return AiPreferences(
      model: model ?? this.model,
      transcriptionLanguage:
          transcriptionLanguage ?? this.transcriptionLanguage,
      outputLanguage: outputLanguage ?? this.outputLanguage,
      customPrompt: customPrompt ?? this.customPrompt,
    );
  }
}

enum AiModel {
  gemini36Flash('Gemini 3.6 Flash', 'google/gemini-3.6-flash'),
  gemini35Flash('Gemini 3.5 Flash', 'google/gemini-3.5-flash'),
  geminiFlash('Gemini 2.5 Flash', 'google/gemini-2.5-flash'),
  geminiPro('Gemini 2.5 Pro', 'google/gemini-2.5-pro');

  const AiModel(this.label, this.openRouterId);
  final String label;
  final String openRouterId;

  static AiModel fromKey(String? key) {
    return AiModel.values.firstWhere(
      (m) => m.name == key,
      orElse: () => AiModel.gemini36Flash,
    );
  }
}

/// Compatibilita' con chiavi vecchie nelle preferenze.
typedef TranscriptionLanguage = AppLanguage;
