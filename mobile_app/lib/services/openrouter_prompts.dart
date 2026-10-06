import '../models/app_language.dart';

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
Read the transcript and return ONLY a valid JSON object with this exact schema:

{
  "title": "short descriptive title (max 60 characters, written in {output_language})",
  "summary": "2 to 4 sentences of plain prose, written in {output_language}"
}

Rules:
- title and summary MUST be written entirely in {output_language}.
- title: concise, reflects the main content, no date/time.
- summary: a short paragraph a person can read in a few seconds. Plain prose only.
  No markdown, no headings, no bullet lists.
- Do NOT include highlights, key_data, speaker_ids, speaker_view, or formatted_transcript.
- Reply with JSON only, no markdown fences or extra text.''';

const noteChatSystemPrompt = '''You are Drop, an AI assistant for a single voice note.
Reply ONLY from the provided note context. If the information is not in the context, say so clearly.
Reply in {output_language}, concisely and helpfully. Bullet lists or light markdown are fine.
When the answer includes source code, a command, or configuration, put it in a fenced markdown block with a language tag. Keep the original indentation and line breaks. Do not wrap the whole reply in one fence, and do not place code inside math delimiters.''';

String buildAnalysisSystemPrompt({String? outputLanguage}) {
  return analysisSystemPromptTemplate.replaceAll(
    '{output_language}',
    outputLanguageLabel(outputLanguage),
  );
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
}) {
  var prompt = 'Trascrizione:\n\n$transcript';
  if (customPrompt != null && customPrompt.trim().isNotEmpty) {
    prompt += '\n\nIstruzioni aggiuntive dell\'utente:\n${customPrompt.trim()}';
  }
  if (language != null) {
    final lang = language.trim().toLowerCase();
    if (lang.isNotEmpty && lang != 'automatic' && lang != 'automatico') {
      prompt =
          'Write the title and the summary in ${outputLanguageLabel(language)}.\n\n$prompt';
    }
  }
  return prompt;
}
