sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

class ChatReasoningDelta extends ChatStreamEvent {
  const ChatReasoningDelta(this.delta);
  final String delta;
}

class ChatContentDelta extends ChatStreamEvent {
  const ChatContentDelta(this.delta);
  final String delta;
}

class ChatStreamDone extends ChatStreamEvent {
  const ChatStreamDone({required this.content, this.reasoning});
  final String content;
  final String? reasoning;
}

class ChatStreamError extends ChatStreamEvent {
  const ChatStreamError(this.message);
  final String message;
}
