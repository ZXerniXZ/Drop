import 'package:drop/models/ai_preferences.dart';
import 'package:drop/services/open_router_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog keeps chat models and drops the rest', () {
    final models = parseOpenRouterModels({
      'data': [
        {
          'id': 'google/gemini-3.8-flash',
          'name': 'Google: Gemini 3.8 Flash',
          'context_length': 1048576,
          'architecture': {
            'input_modalities': ['text'],
            'output_modalities': ['text'],
          },
          'pricing': {'prompt': '0.00000075'},
        },
        {
          'id': 'google/gemini-2.5-flash-image',
          'name': 'Google: Nano Banana',
          'architecture': {
            'input_modalities': ['image', 'text'],
            'output_modalities': ['image', 'text'],
          },
        },
        {
          'id': 'google/lyria-3-pro-preview',
          'name': 'Lyria',
          'architecture': {
            'input_modalities': ['text'],
            'output_modalities': ['text', 'audio'],
          },
        },
        {
          'id': 'google/gemini-3.6-flash:batch',
          'name': 'Google: Gemini 3.6 Flash (batch)',
          'architecture': {
            'input_modalities': ['text'],
            'output_modalities': ['text'],
          },
        },
        {
          'id': '~google/gemini-flash-latest',
          'name': 'Latest',
          'architecture': {
            'input_modalities': ['text'],
            'output_modalities': ['text'],
          },
        },
      ],
    });

    expect(models, hasLength(1));
    expect(models.single.label, 'Gemini 3.8 Flash');
    expect(models.single.contextLabel, '1M');
    expect(models.single.priceLabel, r'$0.75 / 1M');
    expect(isRecommendedOpenRouterModel(models.single.openRouterId), isTrue);
  });

  test('recommended models are the main Gemini flash and pro lines', () {
    expect(isRecommendedOpenRouterModel('google/gemini-2.5-pro'), isTrue);
    expect(isRecommendedOpenRouterModel('google/gemini-3.5-flash-lite'), isFalse);
    expect(isRecommendedOpenRouterModel('openai/gpt-5'), isFalse);
  });

  test('search matches the name and the id', () {
    const models = [
      AiModel(openRouterId: 'google/gemini-2.5-pro', label: 'Gemini 2.5 Pro'),
      AiModel(openRouterId: 'anthropic/claude-sonnet', label: 'Claude Sonnet'),
    ];

    expect(filterOpenRouterModels(models, 'claude'), [models[1]]);
    expect(filterOpenRouterModels(models, '2.5-pro'), [models[0]]);
    expect(filterOpenRouterModels(models, '   '), models);
  });

  test('stored model keys stay compatible', () {
    expect(AiModel.fromKey('geminiFlash').openRouterId, 'google/gemini-2.5-flash');
    expect(
      AiModel.fromKey('anthropic/claude-sonnet-4').label,
      'Claude Sonnet 4',
    );
    expect(AiModel.fromKey(null), AiModel.gemini36Flash);
  });

  test('a free model shows Gratis', () {
    const model = AiModel(
      openRouterId: 'openrouter/free',
      label: 'Free',
      promptPerToken: 0,
    );
    expect(model.priceLabel, 'Gratis');
  });
}
