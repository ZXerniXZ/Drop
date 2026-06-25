class AiPreferences {
  const AiPreferences({
    this.model = AiModel.geminiFlash,
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
  geminiFlash('Gemini 1.5 Flash'),
  geminiPro('Gemini 1.5 Pro');

  const AiModel(this.label);
  final String label;

  static AiModel fromKey(String? key) {
    return AiModel.values.firstWhere(
      (m) => m.name == key,
      orElse: () => AiModel.geminiFlash,
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
