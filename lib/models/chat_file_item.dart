import 'message_model.dart';

/// 从本地聊天记录整理出的一条图片、视频或文件。
class ChatFileItem {
  final String key;
  final MessageType type;
  final String name;
  final String url;
  final int size;
  final DateTime time;
  final int targetId;
  final bool isGroup;
  final String conversationName;
  final String senderName;
  final String content;
  final String localPath;

  const ChatFileItem({
    required this.key,
    required this.type,
    required this.name,
    required this.url,
    required this.size,
    required this.time,
    required this.targetId,
    required this.isGroup,
    required this.conversationName,
    required this.senderName,
    required this.content,
    this.localPath = '',
  });

  ChatFileItem copyWith({String? localPath}) {
    return ChatFileItem(
      key: key,
      type: type,
      name: name,
      url: url,
      size: size,
      time: time,
      targetId: targetId,
      isGroup: isGroup,
      conversationName: conversationName,
      senderName: senderName,
      content: content,
      localPath: localPath ?? this.localPath,
    );
  }

  String get sizeLabel {
    if (size <= 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get typeLabel {
    switch (type) {
      case MessageType.image:
        return '图片';
      case MessageType.video:
        return '视频';
      case MessageType.file:
        return '文件';
      default:
        return '文件';
    }
  }
}
