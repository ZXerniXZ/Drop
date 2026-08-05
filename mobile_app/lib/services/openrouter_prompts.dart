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

const analysisSystemPromptTemplate = '''Sei l'assistente di un'app di note vocali stile Plaud Note.
Analizza la trascrizione e restituisci SOLO un oggetto JSON valido con questo schema esatto:

{
  "title": "titolo breve e descrittivo della nota (max 60 caratteri, in italiano)",
  "summary": "stringa Markdown con sezioni ## Overview, ## Key Decisions e altre sezioni utili",
  "highlights": ["action item o punto chiave 1", "punto 2"],
  "key_data": {
    "location": "luogo dedotto o stringa vuota",
    "participants": ["nome o Speaker 0", "Speaker 1"],
    "tags": "UNO dalla lista consentita"
  },
  "speaker_ids": [0, 0, 1, 1, 0]
}

Tag consentiti (scegline esattamente UNO per key_data.tags): {tag_list}

Regole:
- title: sintetico, riflette il contenuto principale, senza data/ora.
- highlights: 2-8 elementi concreti e actionable quando possibile.
- summary: puoi riassumere liberamente.
- speaker_ids: diarizzazione COMPATTA. Un intero per ogni segmento numerato ricevuto
  (stessa lunghezza dell'elenco). 0 = Speaker 0, 1 = Speaker 1, ecc.
  NON riscrivere il testo dei segmenti: il client lo monta da Whisper.
  Se monologo o non sai distinguere, usa tutti 0.
- key_data.tags: DEVE essere uno dei tag consentiti sopra.
- NON includere speaker_view ne' formatted_transcript.
- Rispondi SOLO con JSON, senza markdown fence o testo extra.''';

const noteChatSystemPrompt = '''Sei Drop, assistente AI per una singola nota vocale.
Rispondi SOLO in base al contesto della nota fornito. Se l'informazione non è nel contesto, dillo chiaramente.
Rispondi in italiano, in modo conciso e utile. Puoi usare elenchi puntati o markdown leggero.''';

String buildAnalysisSystemPrompt(List<String> availableTags) {
  final tags = availableTags.where((t) => t.trim().isNotEmpty).toList();
  final pool = tags.isEmpty ? defaultAnalysisTags : tags;
  return analysisSystemPromptTemplate.replaceAll('{tag_list}', pool.join(' | '));
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
      prompt = 'Lingua richiesta per l\'output: ${language.trim()}\n\n$prompt';
    }
  }
  return prompt;
}
