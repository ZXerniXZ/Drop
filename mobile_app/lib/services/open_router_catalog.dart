import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_preferences.dart';
import 'openrouter_client.dart';
import 'openrouter_prompts.dart';

const _cacheKey = 'openrouter_model_catalog';

/// Gemini principali, senza varianti lite, image, batch o preview.
bool isRecommendedOpenRouterModel(String id) {
  if (!id.startsWith('google/gemini-')) return false;
  if (id.contains(':') ||
      id.contains('image') ||
      id.contains('lite') ||
      id.contains('preview') ||
      id.contains('custom')) {
    return false;
  }
  return id.endsWith('-flash') || id.endsWith('-pro');
}

List<AiModel> filterOpenRouterModels(List<AiModel> models, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return models;
  return models
      .where(
        (model) =>
            model.label.toLowerCase().contains(needle) ||
            model.openRouterId.toLowerCase().contains(needle),
      )
      .toList();
}

List<AiModel> parseOpenRouterModels(Object? body) {
  if (body is! Map) return const [];
  final data = body['data'];
  if (data is! List) return const [];
  final models = <AiModel>[];
  final seen = <String>{};
  for (final item in data) {
    final model = _modelFromJson(item);
    if (model == null || !seen.add(model.openRouterId)) continue;
    models.add(model);
  }
  return models;
}

AiModel? _modelFromJson(Object? item) {
  if (item is! Map) return null;
  final id = item['id']?.toString().trim() ?? '';
  if (!_keepsModel(id, item['architecture'])) return null;
  final name = item['name']?.toString() ?? '';
  final context = item['context_length'];
  final pricing = item['pricing'];
  final prompt = pricing is Map ? pricing['prompt']?.toString() : null;
  return AiModel(
    openRouterId: id,
    label: AiModel.labelFromName(name, id),
    contextLength: context is num ? context.round() : int.tryParse('$context'),
    promptPerToken: double.tryParse(prompt ?? ''),
  );
}

bool _keepsModel(String id, Object? architecture) {
  if (id.isEmpty || id.startsWith('~') || id.contains(':batch')) return false;
  if (id.contains('embed')) return false;
  if (architecture is! Map) return false;
  final inputs = _strings(architecture['input_modalities']);
  final outputs = _strings(architecture['output_modalities']);
  if (!inputs.contains('text') || !outputs.contains('text')) return false;
  final imageAt = outputs.indexOf('image');
  final textAt = outputs.indexOf('text');
  if (imageAt != -1 && imageAt < textAt) return false;
  if (outputs.contains('audio')) return false;
  return true;
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList();
}

class OpenRouterCatalog {
  OpenRouterCatalog._();

  static final OpenRouterCatalog instance = OpenRouterCatalog._();

  List<AiModel>? _memory;

  Future<List<AiModel>> readCache() async {
    if (_memory != null) return _memory!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final models = _modelsFromCache(decoded['models']);
      _memory = models;
      return models;
    } catch (_) {
      return const [];
    }
  }

  Future<List<AiModel>> refresh() async {
    final cached = await readCache();
    try {
      final fresh = await _fetch();
      if (fresh.isEmpty) return cached;
      _memory = fresh;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'models': [
            for (final model in fresh)
              {
                'id': model.openRouterId,
                'label': model.label,
                'context': model.contextLength,
                'price': model.promptPerToken,
              },
          ],
        }),
      );
      return fresh;
    } catch (_) {
      return cached;
    }
  }

  Future<List<AiModel>> _fetch() async {
    final response = await http
        .get(
          Uri.parse(openRouterModelsUrl),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'Drop',
            'HTTP-Referer': openRouterAppReferer,
            'X-Title': openRouterAppTitle,
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('OpenRouter models ${response.statusCode}');
    }
    return parseOpenRouterModels(jsonDecode(response.body));
  }

  List<AiModel> _modelsFromCache(Object? value) {
    if (value is! List) return const [];
    final models = <AiModel>[];
    for (final item in value) {
      if (item is! Map) continue;
      final id = item['id']?.toString().trim() ?? '';
      if (id.isEmpty || !id.contains('/')) continue;
      final context = item['context'];
      final price = item['price'];
      models.add(
        AiModel(
          openRouterId: id,
          label: item['label']?.toString().trim().isNotEmpty == true
              ? item['label'].toString()
              : AiModel.labelFromId(id),
          contextLength: context is num ? context.round() : null,
          promptPerToken: price is num ? price.toDouble() : null,
        ),
      );
    }
    return models;
  }
}
