class ChatTurn {
  const ChatTurn({
    required this.question,
    required this.answer,
    required this.timestamp,
    required this.contextPreview,
    required this.retrievedCount,
  });

  final String question;
  final String answer;
  final DateTime timestamp;
  final String contextPreview;
  final int retrievedCount;

  String get timeLabel {
    final local = timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
