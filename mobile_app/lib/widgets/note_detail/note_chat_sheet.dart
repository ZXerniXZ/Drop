import 'package:flutter/material.dart';

import '../../models/audio_note.dart';
import '../../models/chat_stream_event.dart';
import '../../models/note_chat_message.dart';
import '../../services/local_database_service.dart';
import '../../services/note_chat_service.dart';
import '../../theme/drop_theme.dart';
import '../../widgets/drop_markdown.dart';
import 'ask_ai_bar.dart';
import 'reasoning_accordion.dart';

class NoteChatSheet extends StatefulWidget {
  const NoteChatSheet({
    super.key,
    required this.note,
    this.initialMessage,
  });

  final AudioNote note;
  final String? initialMessage;

  @override
  State<NoteChatSheet> createState() => _NoteChatSheetState();
}

class _NoteChatSheetState extends State<NoteChatSheet> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  List<NoteChatMessage> _messages = [];
  bool _loading = true;
  bool _streaming = false;
  String _streamReasoning = '';
  String _streamContent = '';
  bool _hasContentDelta = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMessages().then((_) {
      final initial = widget.initialMessage?.trim();
      if (initial != null && initial.isNotEmpty) {
        _inputController.text = initial;
        _sendMessage(initial);
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final messages =
        await LocalDatabaseService.instance.getChatMessages(widget.note.id);
    if (!mounted) return;
    setState(() {
      _messages = messages;
      _loading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage(String text) async {
    final message = text.trim();
    if (message.isEmpty || widget.note.isProcessing || _streaming) return;

    setState(() {
      _streaming = true;
      _streamReasoning = '';
      _streamContent = '';
      _hasContentDelta = false;
      _error = null;
    });
    _inputController.clear();

    final userMessage = await NoteChatService.instance.saveUserMessage(
      noteId: widget.note.id,
      content: message,
    );

    setState(() => _messages = [..._messages, userMessage]);
    _scrollToBottom();

    await for (final event in NoteChatService.instance.sendMessageStream(
      note: widget.note,
      message: message,
    )) {
      if (!mounted) return;

      switch (event) {
        case ChatReasoningDelta(:final delta):
          setState(() => _streamReasoning += delta);
          _scrollToBottom();
        case ChatContentDelta(:final delta):
          setState(() {
            _hasContentDelta = true;
            _streamContent += delta;
          });
          _scrollToBottom();
        case ChatStreamDone(:final content, :final reasoning):
          final assistant = await NoteChatService.instance.saveAssistantMessage(
            noteId: widget.note.id,
            content: content,
            reasoning: reasoning,
          );
          if (!mounted) return;
          setState(() {
            _messages = [..._messages, assistant];
            _streaming = false;
            _streamReasoning = '';
            _streamContent = '';
            _hasContentDelta = false;
          });
          _scrollToBottom();
        case ChatStreamError(:final message):
          setState(() {
            _streaming = false;
            _streamReasoning = '';
            _streamContent = '';
            _hasContentDelta = false;
            _error = message;
          });
      }
    }

    if (mounted && _streaming) {
      setState(() => _streaming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          children: [
            _buildHeader(context),
            if (widget.note.isProcessing) _buildProcessingBanner(context),
            if (_error != null) _buildErrorBanner(context),
            Expanded(child: _buildMessageList(context)),
            AskAiBar(
              controller: _inputController,
              enabled: !widget.note.isProcessing && !_streaming,
              hintText: widget.note.isProcessing
                  ? 'Analisi in corso...'
                  : 'Chiedi a Drop su questa nota...',
              onSend: () => _sendMessage(_inputController.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 22),
          ),
          Expanded(
            child: Text(
              'Ask Drop',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DropColors.muted(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Analisi in corso — la chat sarà disponibile al termine.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DropColors.recordRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _error!,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: DropColors.recordRed,
            ),
      ),
    );
  }

  Widget _buildMessageList(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty && !_streaming) {
      return _buildEmptyState(context);
    }

    final itemCount = _messages.length + (_streaming ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < _messages.length) {
          return _ChatBubble(message: _messages[index]);
        }
        return _StreamingBubble(
          reasoning: _streamReasoning,
          content: _streamContent,
          isStreamingReasoning: _streaming && !_hasContentDelta,
          autoCollapseOnContent: _hasContentDelta,
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    const suggestions = [
      'Riassumi in 3 punti',
      'Quali action item?',
      'Chi ha parlato di cosa?',
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Fai una domanda su questa nota',
          style: Theme.of(context).textTheme.titleSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ...suggestions.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: widget.note.isProcessing ? null : () => _sendMessage(s),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: DropColors.border(context)),
              ),
              child: Text(s),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final NoteChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isUser &&
                message.reasoning != null &&
                message.reasoning!.isNotEmpty)
              ReasoningAccordion(reasoning: message.reasoning!),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.onSurface
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(14),
                border: isUser
                    ? null
                    : Border.all(color: DropColors.border(context)),
              ),
              child: DropMarkdown(
                data: message.content,
                fontSize: 13,
                textColor: isUser
                    ? Theme.of(context).colorScheme.surface
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({
    required this.reasoning,
    required this.content,
    required this.isStreamingReasoning,
    required this.autoCollapseOnContent,
  });

  final String reasoning;
  final String content;
  final bool isStreamingReasoning;
  final bool autoCollapseOnContent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reasoning.isNotEmpty || isStreamingReasoning)
              ReasoningAccordion(
                reasoning: reasoning,
                isStreamingReasoning: isStreamingReasoning,
                autoCollapseOnContent: autoCollapseOnContent,
              ),
            if (content.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: DropColors.border(context)),
                ),
                child: DropMarkdown(data: content, fontSize: 13),
              )
            else if (!isStreamingReasoning && reasoning.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void showNoteChatSheet(
  BuildContext context, {
  required AudioNote note,
  String? initialMessage,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => NoteChatSheet(
      note: note,
      initialMessage: initialMessage,
    ),
  );
}
