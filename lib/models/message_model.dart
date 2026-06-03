import 'sender_info_model.dart';

enum MessageType { text, image, video, audio, file }

enum MessageStatus { sending, sent, delivered, read, failed, recalled }

class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String receiverId;
  final MessageType type;
  final String content;
  final String? mediaUrl;
  final DateTime timestamp;
  final bool isRead;
  final bool isSent;
  final bool isSending;
  final MessageStatus status;
  final bool canRecall;
  final SenderInfoModel? senderInfo;
  final GroupInfoModel? groupInfo;

  MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.content,
    this.mediaUrl,
    required this.timestamp,
    this.isRead = false,
    this.isSent = false,
    this.isSending = false,
    this.status = MessageStatus.sent,
    this.canRecall = false,
    this.senderInfo,
    this.groupInfo,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] ?? '',
      conversationId: json['conversation_id'] ?? '',
      senderId: json['sender_id'] ?? '',
      receiverId: json['receiver_id'] ?? '',
      type: MessageType.values.firstWhere(
        (e) => e.name == (json['type'] ?? 'text'),
        orElse: () => MessageType.text,
      ),
      content: json['content'] ?? '',
      mediaUrl: json['media_url'],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      isRead: json['is_read'] ?? false,
      isSent: json['is_sent'] ?? false,
      isSending: false,
      status: json['status'] != null
          ? MessageStatus.values.firstWhere(
              (e) => e.name == json['status'],
              orElse: () => MessageStatus.sent,
            )
          : MessageStatus.sent,
      canRecall: json['can_recall'] ?? false,
      senderInfo: json['senderInfo'] != null
          ? SenderInfoModel.fromJson(json['senderInfo'])
          : null,
      groupInfo: json['groupInfo'] != null
          ? GroupInfoModel.fromJson(json['groupInfo'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'type': type.name,
      'content': content,
      'media_url': mediaUrl,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead,
      'is_sent': isSent,
      'status': status.name,
      'can_recall': canRecall,
      if (senderInfo != null) 'senderInfo': senderInfo!.toJson(),
      if (groupInfo != null) 'groupInfo': groupInfo!.toJson(),
    };
  }

  String get displayText {
    switch (type) {
      case MessageType.image:
        return '[图片]';
      case MessageType.video:
        return '[视频]';
      case MessageType.audio:
        return '[语音]';
      case MessageType.file:
        return '[文件]';
      case MessageType.text:
      default:
        return content.length > 50 ? '${content.substring(0, 50)}...' : content;
    }
  }

  String get senderDisplayName {
    if (senderInfo != null) {
      if (senderInfo!.groupNickname != null && senderInfo!.groupNickname!.isNotEmpty) {
        return senderInfo!.groupNickname!;
      }
      if (senderInfo!.nickname.isNotEmpty) {
        return senderInfo!.nickname;
      }
    }
    return '用户$senderId';
  }

  String? get senderDisplayAvatar {
    return senderInfo?.avatar;
  }

  String? get groupDisplayName {
    return groupInfo?.groupName;
  }

  MessageModel copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? receiverId,
    MessageType? type,
    String? content,
    String? mediaUrl,
    DateTime? timestamp,
    bool? isRead,
    bool? isSent,
    bool? isSending,
    MessageStatus? status,
    bool? canRecall,
    SenderInfoModel? senderInfo,
    GroupInfoModel? groupInfo,
  }) {
    return MessageModel(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      type: type ?? this.type,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      isSent: isSent ?? this.isSent,
      isSending: isSending ?? this.isSending,
      status: status ?? this.status,
      canRecall: canRecall ?? this.canRecall,
      senderInfo: senderInfo ?? this.senderInfo,
      groupInfo: groupInfo ?? this.groupInfo,
    );
  }
}
