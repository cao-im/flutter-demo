import 'file_content.dart';
import 'message_model.dart';
import 'video_content.dart';
import 'voice_content.dart';

class FavoriteItem {
  final int id;
  final int msgMid;
  final int msgType;
  final String content;
  final int fromId;
  final String fromName;
  final String sourceName;
  final int? groupId;
  final DateTime? messageTime;

  const FavoriteItem({
    required this.id,
    required this.msgMid,
    required this.msgType,
    required this.content,
    required this.fromId,
    required this.fromName,
    required this.sourceName,
    required this.groupId,
    required this.messageTime,
  });

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      id: int.tryParse('${json['id']}') ?? 0,
      msgMid: int.tryParse('${json['msgMid']}') ?? 0,
      msgType: int.tryParse('${json['msgType']}') ?? 0,
      content: json['content']?.toString() ?? '',
      fromId: int.tryParse('${json['fromId']}') ?? 0,
      fromName: json['fromName']?.toString() ?? '',
      sourceName: json['sourceName']?.toString() ?? '',
      groupId: int.tryParse('${json['groupId'] ?? ''}'),
      messageTime: DateTime.tryParse(json['messageTime']?.toString() ?? ''),
    );
  }

  MessageType get type {
    switch (msgType) {
      case 1:
        return MessageType.image;
      case 2:
        return MessageType.file;
      case 3:
        return MessageType.audio;
      case 4:
        return MessageType.video;
      default:
        return MessageType.text;
    }
  }

  String get preview {
    switch (type) {
      case MessageType.image:
        return '[图片]';
      case MessageType.audio:
        final seconds = VoiceContent.tryParse(content)?.duration ?? 0;
        return seconds > 0 ? '[语音] $seconds″' : '[语音]';
      case MessageType.video:
        return '[视频]';
      case MessageType.file:
        final file = FileContent.tryParse(content);
        if (file == null || file.name.isEmpty) return '[文件]';
        return '[文件] ${file.name}';
      case MessageType.text:
      case MessageType.notice:
        final text = content.trim();
        if (text.isEmpty) return '[空消息]';
        return text.length > 80 ? '${text.substring(0, 80)}...' : text;
    }
  }

  String? get imageUrl {
    if (type != MessageType.image) return null;
    if (content.startsWith('http')) return content;
    return null;
  }

  String get senderLabel {
    if (fromName.isNotEmpty) return fromName;
    if (fromId > 0) return '用户$fromId';
    return '未知';
  }

  String get sourceLabel => sourceName.isEmpty ? '聊天' : sourceName;

  VideoContent? get video => type == MessageType.video ? VideoContent.tryParse(content) : null;

  FileContent? get file => type == MessageType.file ? FileContent.tryParse(content) : null;
}
