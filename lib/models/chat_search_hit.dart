import 'message_model.dart';

class ChatSearchHit {
  final MessageModel message;
  final bool isGroup;
  final int targetId;

  const ChatSearchHit({
    required this.message,
    required this.isGroup,
    required this.targetId,
  });
}
