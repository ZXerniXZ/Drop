import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_preferences.dart';

class AppPreferencesService {
  AppPreferencesService._();

  static final AppPreferencesService instance = AppPreferencesService._();

  static const _modelKey = 'ai_model';
  static const _languageKey = 'transcription_language';
  static const _promptKey = 'custom_prompt';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _store {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('AppPreferencesService not initialized. Call init() first.');
    }
    return prefs;
  }

  Future<AiPreferences> loadAiPreferences() async {
    await init();
    return AiPreferences(
      model: AiModel.fromKey(_store.getString(_modelKey)),
      transcriptionLanguage: TranscriptionLanguage.fromKey(
        _store.getString(_languageKey),
      ),
      customPrompt: _store.getString(_promptKey) ?? '',
    );
  }

  Future<void> saveAiPreferences(AiPreferences prefs) async {
    await init();
    await _store.setString(_modelKey, prefs.model.name);
    await _store.setString(_languageKey, prefs.transcriptionLanguage.name);
    await _store.setString(_promptKey, prefs.customPrompt);
  }
}
