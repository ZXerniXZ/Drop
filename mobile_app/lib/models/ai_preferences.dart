import 'app_language.dart';

class AiPreferences {
  const AiPreferences({
    this.model = AiModel.gemini36Flash,
    this.transcriptionLanguage = AppLanguage.automatic,
    this.outputLanguage = AppLanguage.italian,
    this.customPrompt = '',
    this.noiseReduction = false,
  });

  final AiModel model;
  final AppLanguage transcriptionLanguage;
  final AppLanguage outputLanguage;
  final String customPrompt;
  final bool noiseReduction;

  AiPreferences copyWith({
    AiModel? model,
    AppLanguage? transcriptionLanguage,
    AppLanguage? outputLanguage,
    String? customPrompt,
    bool? noiseReduction,
  }) {
    return AiPreferences(
      model: model ?? this.model,
      transcriptionLanguage:
          transcriptionLanguage ?? this.transcriptionLanguage,
      outputLanguage: outputLanguage ?? this.outputLanguage,
      customPrompt: customPrompt ?? this.customPrompt,
      noiseReduction: noiseReduction ?? this.noiseReduction,
    );
  }
}

class AiModel {
  const AiModel({
    required this.openRouterId,
    required this.label,
    this.contextLength,
    this.promptPerToken,
  });

  final String openRouterId;
  final String label;
  final int? contextLength;

  /// Prezzo prompt in dollari per token. Negativo o assente: non mostrarlo.
  final double? promptPerToken;

  static const gemini36Flash = AiModel(
    openRouterId: 'google/gemini-3.6-flash',
    label: 'Gemini 3.6 Flash',
  );

  static const gemini35Flash = AiModel(
    openRouterId: 'google/gemini-3.5-flash',
    label: 'Gemini 3.5 Flash',
  );

  static const geminiFlash = AiModel(
    openRouterId: 'google/gemini-2.5-flash',
    label: 'Gemini 2.5 Flash',
  );

  static const geminiPro = AiModel(
    openRouterId: 'google/gemini-2.5-pro',
    label: 'Gemini 2.5 Pro',
  );

  /// Usati se il catalogo non si carica.
  static const fallbacks = <AiModel>[
    gemini36Flash,
    gemini35Flash,
    geminiFlash,
    geminiPro,
  ];

  static const _legacyIds = <String, String>{
    'gemini36Flash': 'google/gemini-3.6-flash',
    'gemini35Flash': 'google/gemini-3.5-flash',
    'geminiFlash': 'google/gemini-2.5-flash',
    'geminiPro': 'google/gemini-2.5-pro',
  };

  static AiModel fromKey(String? key) {
    final raw = key?.trim() ?? '';
    if (raw.isEmpty) return gemini36Flash;
    final legacy = _legacyIds[raw];
    if (legacy != null) {
      return fallbacks.firstWhere((model) => model.openRouterId == legacy);
    }
    if (raw.contains('/')) {
      return AiModel(openRouterId: raw, label: labelFromId(raw));
    }
    return gemini36Flash;
  }

  static String labelFromId(String id) {
    final slug = id.split('/').last.replaceAll(':', ' ');
    final parts = slug.split(RegExp(r'[-_\s]+')).where((part) => part.isNotEmpty);
    return parts.map((part) {
      final first = part[0];
      if (RegExp(r'[a-z]').hasMatch(first)) {
        return first.toUpperCase() + part.substring(1);
      }
      return part;
    }).join(' ');
  }

  static String labelFromName(String name, String id) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return labelFromId(id);
    final split = trimmed.indexOf(': ');
    if (split > 0 && split <= 32) {
      final rest = trimmed.substring(split + 2).trim();
      if (rest.isNotEmpty) return rest;
    }
    return trimmed;
  }

  String? get contextLabel {
    final length = contextLength;
    if (length == null || length <= 0) return null;
    if (length >= 1000000) {
      final millions = length / 1000000;
      final tenths = (millions * 10).round() / 10;
      if (tenths == tenths.roundToDouble()) return '${tenths.round()}M';
      return '${tenths.toStringAsFixed(1)}M';
    }
    if (length >= 1000) return '${length ~/ 1000}k';
    return '$length';
  }

  String? get priceLabel {
    final price = promptPerToken;
    if (price == null || price < 0) return null;
    if (price == 0) return 'Gratis';
    final perMillion = price * 1000000;
    if (perMillion < 0.01) return r'< $0.01 / 1M';
    if (perMillion >= 10) {
      final digits = perMillion == perMillion.roundToDouble() ? 0 : 1;
      return '\$${perMillion.toStringAsFixed(digits)} / 1M';
    }
    return '\$${perMillion.toStringAsFixed(2)} / 1M';
  }

  String get detail {
    return [
      openRouterId,
      contextLabel,
      priceLabel,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is AiModel && other.openRouterId == openRouterId;

  @override
  int get hashCode => openRouterId.hashCode;
}

/// Compatibilita' con chiavi vecchie nelle preferenze.
typedef TranscriptionLanguage = AppLanguage;
