class AppLanguage {
  const AppLanguage({
    required this.id,
    required this.label,
    this.code,
  });

  final String id;
  final String label;
  final String? code;

  bool get isAutomatic => id == 'automatic' || code == null;

  @override
  bool operator ==(Object other) => other is AppLanguage && other.id == id;

  @override
  int get hashCode => id.hashCode;

  static const automatic = AppLanguage(
    id: 'automatic',
    label: 'Auto',
    code: null,
  );

  static const italian = AppLanguage(id: 'italian', label: 'Italiano', code: 'it');
  static const english = AppLanguage(id: 'english', label: 'English', code: 'en');
  static const spanish = AppLanguage(id: 'spanish', label: 'Español', code: 'es');
  static const french = AppLanguage(id: 'french', label: 'Français', code: 'fr');
  static const german = AppLanguage(id: 'german', label: 'Deutsch', code: 'de');
  static const portuguese = AppLanguage(
    id: 'portuguese',
    label: 'Português',
    code: 'pt',
  );
  static const dutch = AppLanguage(id: 'dutch', label: 'Nederlands', code: 'nl');
  static const polish = AppLanguage(id: 'polish', label: 'Polski', code: 'pl');
  static const romanian = AppLanguage(id: 'romanian', label: 'Română', code: 'ro');
  static const russian = AppLanguage(id: 'russian', label: 'Русский', code: 'ru');
  static const chinese = AppLanguage(id: 'chinese', label: '中文', code: 'zh');
  static const japanese = AppLanguage(id: 'japanese', label: '日本語', code: 'ja');
  static const korean = AppLanguage(id: 'korean', label: '한국어', code: 'ko');
  static const arabic = AppLanguage(id: 'arabic', label: 'العربية', code: 'ar');
  static const hindi = AppLanguage(id: 'hindi', label: 'हिन्दी', code: 'hi');
  static const turkish = AppLanguage(id: 'turkish', label: 'Türkçe', code: 'tr');

  static const spoken = <AppLanguage>[
    italian,
    english,
    spanish,
    french,
    german,
    portuguese,
    dutch,
    polish,
    romanian,
    russian,
    chinese,
    japanese,
    korean,
    arabic,
    hindi,
    turkish,
  ];

  static const sourceChoices = <AppLanguage>[automatic, ...spoken];

  static AppLanguage fromKey(String? key) {
    if (key == null || key.trim().isEmpty) return automatic;
    final normalized = key.trim().toLowerCase();
    if (normalized == 'automatic' ||
        normalized == 'automatico' ||
        normalized == 'auto') {
      return automatic;
    }
    for (final language in spoken) {
      if (language.id == normalized ||
          language.code == normalized ||
          language.label.toLowerCase() == normalized) {
        return language;
      }
    }
    return automatic;
  }

  static AppLanguage outputFromKey(String? key) {
    final language = fromKey(key);
    if (language.isAutomatic) return italian;
    return language;
  }
}
