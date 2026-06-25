import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_preferences.dart';
import '../models/note_tags_config.dart';

class AppPreferencesService {
  AppPreferencesService._();

  static final AppPreferencesService instance = AppPreferencesService._();

  static const _modelKey = 'ai_model';
  static const _languageKey = 'transcription_language';
  static const _promptKey = 'custom_prompt';
  static const _tagsKey = 'note_tags';

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

  Future<NoteTagsConfig> loadNoteTags() async {
    await init();
    final raw = _store.getString(_tagsKey);
    if (raw == null || raw.isEmpty) {
      return const NoteTagsConfig();
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final tags = decoded.map((e) => e.toString().trim()).where((t) => t.isNotEmpty).toList();
      if (tags.isEmpty) return const NoteTagsConfig();
      return NoteTagsConfig(tags: tags);
    } catch (_) {
      return const NoteTagsConfig();
    }
  }

  Future<void> saveNoteTags(NoteTagsConfig config) async {
    await init();
    final unique = <String>[];
    for (final tag in config.tags) {
      final t = tag.trim();
      if (t.isEmpty) continue;
      if (!unique.any((u) => u.toLowerCase() == t.toLowerCase())) {
        unique.add(t);
      }
    }
    await _store.setString(
      _tagsKey,
      jsonEncode(unique.isEmpty ? NoteTagsConfig.defaultTags : unique),
    );
  }
}
