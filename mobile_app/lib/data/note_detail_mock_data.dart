class MockActionItem {
  const MockActionItem({
    required this.time,
    required this.text,
    this.checked = false,
  });

  final String time;
  final String text;
  final bool checked;
}

class MockSpeakerBlock {
  const MockSpeakerBlock({
    required this.speaker,
    required this.time,
    required this.text,
    this.isActive = false,
  });

  final String speaker;
  final String time;
  final String text;
  final bool isActive;
}

class NoteDetailMockData {
  NoteDetailMockData._();

  static const location = 'Ufficio — Via Roma 12, Milano';
  static const attendees = 'Marco, Giulia, Speaker 0, Speaker 1';

  static const actionItems = [
    MockActionItem(
      time: '04:12',
      text: 'Confermare le due opzioni di voiceover con il team creativo.',
    ),
    MockActionItem(
      time: '12:45',
      text: 'Inviare la palette colori neutra al reparto scenografia.',
    ),
    MockActionItem(
      time: '18:30',
      text: 'Fissare la prossima riunione di allineamento per martedì.',
    ),
  ];

  static List<String> summaryParagraphs(String? realSummary) {
    if (realSummary != null && realSummary.trim().isNotEmpty) {
      return realSummary
          .split(RegExp(r'\n\s*\n'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
    }

    return const [
      'Questo documento riassume una riunione di pianificazione pre-produzione. '
          'Il team ha discusso elementi creativi e logistici, inclusa la strategia '
          'del voiceover e la direzione visiva del progetto.',
      'Le decisioni principali includono la registrazione di due opzioni di '
          'voiceover, l\'adozione di una palette neutra per il set e la definizione '
          'del calendario delle riprese per la settimana successiva.',
      'I prossimi passi prevedono la condivisione del materiale con gli stakeholder '
          'e la validazione finale dello script entro venerdì.',
    ];
  }

  static const speakerBlocks = [
    MockSpeakerBlock(
      speaker: 'Speaker 0',
      time: '00:00',
      text:
          'Okay, iniziamo. Abbiamo molto da coprire sulla direzione visiva del progetto.',
    ),
    MockSpeakerBlock(
      speaker: 'Speaker 1',
      time: '00:15',
      text:
          'Sì, pensavo di restare su una palette molto neutra. Bianchi, grigi e toni terra soft.',
      isActive: true,
    ),
    MockSpeakerBlock(
      speaker: 'Speaker 0',
      time: '00:32',
      text:
          'Concordo. Per il voiceover abbiamo confermato entrambe le opzioni di registrazione?',
    ),
    MockSpeakerBlock(
      speaker: 'Speaker 1',
      time: '00:48',
      text:
          'Sì, registriamo una versione interna e una con il doppiatore esterno entro giovedì.',
    ),
  ];
}
