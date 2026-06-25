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
Analizza la trascrizione grezza e restituisci SOLO un oggetto JSON valido con questo schema esatto:

{
  "title": "titolo breve e descrittivo della nota (max 60 caratteri, in italiano)",
  "summary": "stringa Markdown con sezioni ## Overview, ## Key Decisions e altre sezioni utili",
  "highlights": ["action item o punto chiave 1", "punto 2"],
  "key_data": {
    "location": "luogo dedotto o stringa vuota",
    "participants": ["nome o Speaker 0", "Speaker 1"],
    "tags": "UNO dalla lista consentita"
  },
  "speaker_view": [
    {"speaker": "Speaker 0", "text": "testo pronunciato", "time": "00:00"}
  ],
  "formatted_transcript": "trascrizione formattata con etichette speaker per lettura lineare"
}

Tag consentiti (scegline esattamente UNO per key_data.tags): {tag_list}

Regole:
- title: sintetico, riflette il contenuto principale, senza data/ora.
- highlights: 2-8 elementi concreti e actionable quando possibile.
- speaker_view: separa logicamente il dialogo per speaker; se monologo usa Speaker 0.
- key_data.tags: DEVE essere uno dei tag consentiti sopra.
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
}) {
  var prompt = 'Trascrizione grezza:\n\n$transcript';
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
