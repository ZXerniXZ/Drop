class AiPreferences {
  const AiPreferences({
    this.model = AiModel.gemini35Flash,
    this.transcriptionLanguage = TranscriptionLanguage.automatic,
    this.customPrompt = '',
  });

  final AiModel model;
  final TranscriptionLanguage transcriptionLanguage;
  final String customPrompt;

  AiPreferences copyWith({
    AiModel? model,
    TranscriptionLanguage? transcriptionLanguage,
    String? customPrompt,
  }) {
    return AiPreferences(
      model: model ?? this.model,
      transcriptionLanguage:
          transcriptionLanguage ?? this.transcriptionLanguage,
      customPrompt: customPrompt ?? this.customPrompt,
    );
  }
}

enum AiModel {
  gemini35Flash('Gemini 3.5 Flash', 'google/gemini-3.5-flash'),
  geminiFlash('Gemini 2.5 Flash', 'google/gemini-2.5-flash'),
  geminiPro('Gemini 2.5 Pro', 'google/gemini-2.5-pro');

  const AiModel(this.label, this.openRouterId);
  final String label;
  final String openRouterId;

  static AiModel fromKey(String? key) {
    return AiModel.values.firstWhere(
      (m) => m.name == key,
      orElse: () => AiModel.gemini35Flash,
    );
  }
}

enum TranscriptionLanguage {
  automatic('Automatico'),
  italian('Italiano'),
  english('Inglese');

  const TranscriptionLanguage(this.label);
  final String label;

  static TranscriptionLanguage fromKey(String? key) {
    return TranscriptionLanguage.values.firstWhere(
      (l) => l.name == key,
      orElse: () => TranscriptionLanguage.automatic,
    );
  }
}
