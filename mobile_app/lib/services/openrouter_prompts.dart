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
    {"speaker": "Speaker 0", "text": "testo INTEGRALE del turno, parola per parola", "time": "00:00"}
  ],
  "formatted_transcript": "trascrizione formattata con etichette speaker, testo integrale"
}

Tag consentiti (scegline esattamente UNO per key_data.tags): {tag_list}

Regole:
- title: sintetico, riflette il contenuto principale, senza data/ora.
- highlights: 2-8 elementi concreti e actionable quando possibile.
- summary: e' l'UNICO campo in cui puoi riassumere.
- speaker_view: trascrizione VERBATIM spezzata per turno di parola.
  * Un blocco per ogni intervento (quando cambia chi parla), NON un riassunto per speaker.
  * "text" deve riportare le parole esatte della trascrizione grezza, senza parafrasare,
    condensare, omettere o correggere il senso.
  * Copri l'intera trascrizione: la concatenazione dei "text" deve ricostruire
    sostanzialmente tutto il contenuto parlato.
  * Se monologo: usa Speaker 0 con uno o piu' blocchi sequenziali.
  * "time" e' il timestamp di inizio del turno (MM:SS) se deducibile, altrimenti "00:00".
- formatted_transcript: stessa regola di fedelta' della speaker_view, in forma lineare
  con etichette speaker (es. "[Speaker 0 - 00:00]: ...").
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
  var prompt =
      'Trascrizione grezza (da riportare verbatim in speaker_view e '
      'formatted_transcript; non riassumere quei campi):\n\n$transcript';
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
