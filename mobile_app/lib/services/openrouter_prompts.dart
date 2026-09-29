import '../models/app_language.dart';
import 'speaker_assembly.dart';

const openRouterAppReferer = 'https://github.com/ZXerniXZ/Drop';
const openRouterAppTitle = 'Drop';

const defaultAnalysisTags = [
  'Meeting',
  'Lezione',
  'Diario',
  'Lavoro',
  'Intervista',
  'Brainstorm',
  'Memo',
  'Chiamata',
];

const analysisSystemPromptTemplate = '''You are the assistant for a voice-notes app.
Analyze the transcript and return ONLY a valid JSON object with this exact schema:

{
  "title": "short descriptive title (max 60 characters, written in {output_language})",
  "summary": "Markdown string with ## Overview, ## Key Decisions and other useful sections, written in {output_language}",
  "highlights": ["action item or key point 1", "point 2"],
  "key_data": {
    "location": "inferred place or empty string",
    "participants": ["name or Speaker 0", "Speaker 1"],
    "tags": "EXACTLY ONE from the allowed list"
  },
  "speaker_ids": [0, 0, 1, 1, 0]
}

Allowed tags (pick exactly ONE for key_data.tags): {tag_list}

Rules:
- title, summary, and highlights MUST be written entirely in {output_language}.
- title: concise, reflects the main content, no date/time.
- highlights: 2-8 concrete, actionable items when possible.
- summary: you may paraphrase freely.
- speaker_ids: COMPACT diarization. One integer per numbered segment received
  (same length as the list). 0 = Speaker 0, 1 = Speaker 1, etc.
  Do NOT rewrite segment text: the client assembles it from Whisper.
  If it is a monologue or you cannot tell speakers apart, use all 0.
- key_data.tags: MUST be one of the allowed tags above.
- Do NOT include speaker_view or formatted_transcript.
- Reply with JSON only, no markdown fences or extra text.''';

const noteChatSystemPrompt = '''You are Drop, an AI assistant for a single voice note.
Reply ONLY from the provided note context. If the information is not in the context, say so clearly.
Reply in {output_language}, concisely and helpfully. Bullet lists or light markdown are fine.''';

String buildAnalysisSystemPrompt(
  List<String> availableTags, {
  String? outputLanguage,
}) {
  final tags = availableTags.where((t) => t.trim().isNotEmpty).toList();
  final pool = tags.isEmpty ? defaultAnalysisTags : tags;
  final languageLabel = outputLanguageLabel(outputLanguage);
  return analysisSystemPromptTemplate
      .replaceAll('{tag_list}', pool.join(' | '))
      .replaceAll('{output_language}', languageLabel);
}

String outputLanguageLabel(String? language) {
  return AppLanguage.outputFromKey(language).label;
}

String buildNoteChatSystemPrompt({String? outputLanguage}) {
  return noteChatSystemPrompt.replaceAll(
    '{output_language}',
    outputLanguageLabel(outputLanguage),
  );
}

String buildAnalysisUserPrompt({
  required String transcript,
  String? customPrompt,
  String? language,
  List<Map<String, dynamic>>? segments,
}) {
  var prompt = 'Trascrizione grezza (per titolo, summary, highlights):\n\n$transcript';
  if (segments != null && segments.isNotEmpty) {
    final numbered = formatSegmentsForDiarization(segments);
    prompt +=
        '\n\nCi sono ${segments.length} segmenti Whisper. Restituisci '
        'speaker_ids con esattamente ${segments.length} interi (0-based). '
        'Non riscrivere il testo dei segmenti.\n\n'
        'Segmenti numerati:\n\n$numbered';
  }
  if (customPrompt != null && customPrompt.trim().isNotEmpty) {
    prompt += '\n\nIstruzioni aggiuntive dell\'utente:\n${customPrompt.trim()}';
  }
  if (language != null) {
    final lang = language.trim().toLowerCase();
    if (lang.isNotEmpty && lang != 'automatic' && lang != 'automatico') {
      prompt =
          'Write title, summary, and highlights in ${outputLanguageLabel(language)}.\n\n$prompt';
    }
  }
  return prompt;
}
