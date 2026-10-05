import 'dart:convert';

class SpeakerBlock {
  const SpeakerBlock({
    required this.speaker,
    required this.text,
    this.time,
  });

  final String speaker;
  final String text;
  final String? time;

  factory SpeakerBlock.fromMap(Map<String, dynamic> map) {
    return SpeakerBlock(
      speaker: map['speaker'] as String? ?? 'Speaker 0',
      text: map['text'] as String? ?? '',
      time: map['time'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'speaker': speaker,
        'text': text,
        if (time != null) 'time': time,
      };
}

class NoteFact {
  const NoteFact({required this.lead, required this.detail});

  final String lead;
  final String detail;

  bool get isEmpty => lead.trim().isEmpty && detail.trim().isEmpty;

  factory NoteFact.fromMap(
    Map<String, dynamic> map, {
    required String leadKey,
  }) {
    return NoteFact(
      lead: map[leadKey]?.toString().trim() ?? '',
      detail: map['what']?.toString().trim() ??
          map['detail']?.toString().trim() ??
          '',
    );
  }

  Map<String, dynamic> toMap(String leadKey) => {
        leadKey: lead,
        'what': detail,
      };
}

class MindMapNode {
  const MindMapNode({
    required this.title,
    this.body = '',
    this.children = const [],
  });

  final String title;
  final String body;
  final List<MindMapNode> children;

  bool get opens => body.trim().isNotEmpty || children.isNotEmpty;

  factory MindMapNode.fromMap(Map<String, dynamic> map) {
    final rawChildren = map['children'] ?? map['nodes'];
    final children = rawChildren is List
        ? rawChildren
            .whereType<Map>()
            .map((item) => MindMapNode.fromMap(Map<String, dynamic>.from(item)))
            .where((node) => node.title.isNotEmpty || node.body.isNotEmpty)
            .toList()
        : const <MindMapNode>[];
    final title = map['title']?.toString().trim() ?? '';
    final body = (map['body'] ?? map['explanation'] ?? map['detail'])
            ?.toString()
            .trim() ??
        '';
    return MindMapNode(title: title, body: body, children: children);
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'body': body,
        'children': children.map((node) => node.toMap()).toList(),
      };
}

class NoteStructuredData {
  const NoteStructuredData({
    this.highlights = const [],
    this.location = '',
    this.participants = const [],
    this.tagLabel = '',
    this.deadlines = const [],
    this.figures = const [],
    this.decisions = const [],
    this.speakerView = const [],
    this.mindMap = const [],
    this.analysisState = const {},
    this.checkedHighlights = const [],
  });

  static const highlightsKind = 'highlights';
  static const speakersKind = 'speakers';
  static const keyDataKind = 'key_data';
  static const mindMapKind = 'mind_map';

  final List<String> highlights;
  final String location;
  final List<String> participants;
  final String tagLabel;
  final List<NoteFact> deadlines;
  final List<NoteFact> figures;
  final List<String> decisions;
  final List<SpeakerBlock> speakerView;
  final List<MindMapNode> mindMap;
  final Map<String, String> analysisState;
  final List<String> checkedHighlights;

  bool isReady(String kind) => analysisState[kind] == 'ready';

  bool get hasPeople => participants.isNotEmpty;
  bool get hasLocation => location.trim().isNotEmpty;
  bool get hasDeadlines => deadlines.any((fact) => !fact.isEmpty);
  bool get hasFigures => figures.any((fact) => !fact.isEmpty);
  bool get hasDecisions => decisions.isNotEmpty;
  bool get hasTag => tagLabel.trim().isNotEmpty;

  bool get keyDataHasSubstance =>
      hasPeople || hasLocation || hasDeadlines || hasFigures || hasDecisions;

  /// Note vecchie: il riassunto a sezioni significava che le tre analisi
  /// erano gia' state fatte, anche se una lista e' rimasta vuota.
  NoteStructuredData withLegacySummary(String summary) {
    if (!summary.contains('##')) return this;
    return copyWith(
      analysisState: {
        ...analysisState,
        highlightsKind: analysisState[highlightsKind] ?? 'ready',
        speakersKind: analysisState[speakersKind] ?? 'ready',
        keyDataKind: analysisState[keyDataKind] ?? 'ready',
      },
    );
  }

  NoteStructuredData copyWith({
    List<String>? highlights,
    String? location,
    List<String>? participants,
    String? tagLabel,
    List<NoteFact>? deadlines,
    List<NoteFact>? figures,
    List<String>? decisions,
    List<SpeakerBlock>? speakerView,
    List<MindMapNode>? mindMap,
    Map<String, String>? analysisState,
    List<String>? checkedHighlights,
  }) {
    return NoteStructuredData(
      highlights: highlights ?? this.highlights,
      location: location ?? this.location,
      participants: participants ?? this.participants,
      tagLabel: tagLabel ?? this.tagLabel,
      deadlines: deadlines ?? this.deadlines,
      figures: figures ?? this.figures,
      decisions: decisions ?? this.decisions,
      speakerView: speakerView ?? this.speakerView,
      mindMap: mindMap ?? this.mindMap,
      analysisState: analysisState ?? this.analysisState,
      checkedHighlights: checkedHighlights ?? this.checkedHighlights,
    );
  }

  factory NoteStructuredData.fromResponse(Map<String, dynamic> data) {
    final highlightsRaw = data['highlights'];
    final highlights = highlightsRaw is List
        ? highlightsRaw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];

    final keyData = data['key_data'];
    var location = '';
    var participants = <String>[];
    var tagLabel = '';
    var deadlines = <NoteFact>[];
    var figures = <NoteFact>[];
    var decisions = <String>[];
    if (keyData is Map) {
      final map = Map<String, dynamic>.from(keyData);
      location = map['location']?.toString().trim() ?? '';
      final people = map['participants'];
      if (people is List) {
        participants = people
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      tagLabel = map['tags']?.toString().trim() ?? '';
      deadlines = _facts(map['deadlines'], leadKey: 'when');
      figures = _facts(map['figures'], leadKey: 'value');
      final decisionRaw = map['decisions'];
      if (decisionRaw is List) {
        decisions = decisionRaw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }

    final speakerRaw = data['speaker_view'];
    final speakerView = speakerRaw is List
        ? speakerRaw
            .whereType<Map>()
            .map((item) => SpeakerBlock.fromMap(Map<String, dynamic>.from(item)))
            .where((b) => b.text.isNotEmpty)
            .toList()
        : <SpeakerBlock>[];

    final checkedRaw = data['checked_highlights'];
    final checked = checkedRaw is List
        ? checkedRaw
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];

    final mindRaw = data['mind_map'];
    final mindMap = mindRaw is List
        ? mindRaw
            .whereType<Map>()
            .map((item) => MindMapNode.fromMap(Map<String, dynamic>.from(item)))
            .where((node) => node.title.isNotEmpty || node.body.isNotEmpty)
            .toList()
        : <MindMapNode>[];

    return NoteStructuredData(
      highlights: highlights,
      location: location,
      participants: participants,
      tagLabel: tagLabel,
      deadlines: deadlines,
      figures: figures,
      decisions: decisions,
      speakerView: speakerView,
      mindMap: mindMap,
      analysisState: _analysisState(
        data,
        summary: data['summary']?.toString() ?? '',
        highlights: highlights,
        speakerView: speakerView,
        mindMap: mindMap,
        hasSubstance: location.isNotEmpty ||
            participants.isNotEmpty ||
            deadlines.isNotEmpty ||
            figures.isNotEmpty ||
            decisions.isNotEmpty,
      ),
      checkedHighlights: checked,
    );
  }

  factory NoteStructuredData.fromJsonString(String? json) {
    if (json == null || json.isEmpty) return const NoteStructuredData();
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return NoteStructuredData.fromResponse(decoded);
    } catch (_) {
      return const NoteStructuredData();
    }
  }

  String toJsonString() {
    return jsonEncode({
      'highlights': highlights,
      'key_data': {
        'location': location,
        'participants': participants,
        'tags': tagLabel,
        'deadlines': deadlines.map((fact) => fact.toMap('when')).toList(),
        'figures': figures.map((fact) => fact.toMap('value')).toList(),
        'decisions': decisions,
      },
      'speaker_view': speakerView.map((b) => b.toMap()).toList(),
      'mind_map': mindMap.map((node) => node.toMap()).toList(),
      'analysis_state': analysisState,
      'checked_highlights': checkedHighlights,
    });
  }

  Map<String, dynamic> keyDataPayload() => {
        'location': location,
        'participants': participants,
        'tags': tagLabel,
        'deadlines': deadlines.map((fact) => fact.toMap('when')).toList(),
        'figures': figures.map((fact) => fact.toMap('value')).toList(),
        'decisions': decisions,
      };

  static List<NoteFact> _facts(dynamic raw, {required String leadKey}) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => NoteFact.fromMap(
            Map<String, dynamic>.from(item),
            leadKey: leadKey,
          ),
        )
        .where((fact) => !fact.isEmpty)
        .toList();
  }

  static Map<String, String> _analysisState(
    Map<String, dynamic> data, {
    required String summary,
    required List<String> highlights,
    required List<SpeakerBlock> speakerView,
    required List<MindMapNode> mindMap,
    required bool hasSubstance,
  }) {
    final state = <String, String>{};
    final raw = data['analysis_state'];
    if (raw is Map) {
      raw.forEach((key, value) {
        final label = value?.toString() ?? '';
        if (label.isNotEmpty) state[key.toString()] = label;
      });
    }
    if (summary.contains('##')) {
      state.putIfAbsent(highlightsKind, () => 'ready');
      state.putIfAbsent(speakersKind, () => 'ready');
      state.putIfAbsent(keyDataKind, () => 'ready');
      return state;
    }
    if (highlights.isNotEmpty) {
      state.putIfAbsent(highlightsKind, () => 'ready');
    }
    if (speakerView.isNotEmpty) {
      state.putIfAbsent(speakersKind, () => 'ready');
    }
    if (mindMap.isNotEmpty) {
      state.putIfAbsent(mindMapKind, () => 'ready');
    }
    if (hasSubstance) {
      state.putIfAbsent(keyDataKind, () => 'ready');
    }
    return state;
  }
}
