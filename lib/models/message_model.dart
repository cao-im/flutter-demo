import 'sender_info_model.dart';
import 'voice_content.dart';
import 'file_content.dart';

enum MessageType { text, image, video, audio, file, notice }

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
  final int? mid; // SDK 生成的雪花算法消息ID
  /// mid 的十进制原文。同一条消息在 Web 上可能无法用 int 精确比较。
  final String? midKey;
  final int? replyMsgId;
  final String? replyPreview;
  final String? replySenderName;
  /// 群消息已读人数。私聊不使用。
  final int? readCount;
  /// 本机副本路径。有这个路径时优先用本地文件打开。
  final String? localPath;

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
    this.mid,
    this.midKey,
    this.replyMsgId,
    this.replyPreview,
    this.replySenderName,
    this.readCount,
    this.localPath,
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
      mid: json['mid'] is int ? json['mid'] as int : int.tryParse('${json['mid'] ?? ''}'),
      midKey: json['mid']?.toString(),
      replyMsgId: json['replyMsgId'],
      replyPreview: json['replyPreview'],
      replySenderName: json['replySenderName'],
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
      if (replyMsgId != null) 'replyMsgId': replyMsgId,
      if (replyPreview != null) 'replyPreview': replyPreview,
      if (replySenderName != null) 'replySenderName': replySenderName,
    };
  }

  /// 图片地址：本机副本优先，否则用上传地址。
  String? get imageSource {
    if (type != MessageType.image) return null;
    final local = localPath?.trim() ?? '';
    if (local.isNotEmpty) return local;
    final url = mediaUrl;
    if (url != null && url.isNotEmpty) return url;
    if (content.startsWith('http')) return content;
    return null;
  }

  VoiceContent? get _voice =>
      type == MessageType.audio ? VoiceContent.tryParse(content) : null;

  /// 可播放地址：发送中用本地文件，发出后用上传地址。
  String? get voiceSource {
    if (type != MessageType.audio) return null;
    final url = mediaUrl;
    if (url != null && url.isNotEmpty) return url;
    return _voice?.url;
  }

  int get voiceDuration {
    final seconds = _voice?.duration ?? 1;
    if (seconds < 1) return 1;
    if (seconds > 60) return 60;
    return seconds;
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
        final file = FileContent.tryParse(content);
        if (file == null || file.name.isEmpty) return '[文件]';
        return '[文件] ${file.name}';
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

  /// 私聊通话记录。文案由服务端写成「语音通话…」或「视频通话…」。
  bool get isCallRecord {
    if (type != MessageType.notice) return false;
    final text = content.trimLeft();
    return text.startsWith('语音通话') || text.startsWith('视频通话');
  }

  bool get callWithVideo => content.trimLeft().startsWith('视频通话');

  /// 群提示在自己这边显示「你」，其他人显示操作者名字。
  String noticeText(String? myId) {
    const marker = '修改群名为';
    final index = content.indexOf(marker);
    if (index < 0) return content;
    final mine = myId != null && myId.isNotEmpty && senderId == myId;
    if (mine) return '你${content.substring(index)}';
    return content;
  }

  /// 被引用时展示的摘要
  String get quoteText {
    switch (type) {
      case MessageType.image:
        return '[图片]';
      case MessageType.audio:
        return '[语音]';
      case MessageType.video:
        return '[视频]';
      case MessageType.file:
        final file = FileContent.tryParse(content);
        if (file == null || file.name.isEmpty) return '[文件]';
        return '[文件] ${file.name}';
      case MessageType.notice:
        return content;
      case MessageType.text:
        final text = content.replaceAll('\n', ' ').trim();
        if (text.length <= 60) return text;
        return '${text.substring(0, 60)}…';
    }
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
    int? mid,
    String? midKey,
    int? replyMsgId,
    String? replyPreview,
    String? replySenderName,
    int? readCount,
    String? localPath,
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
      mid: mid ?? this.mid,
      midKey: midKey ?? this.midKey,
      replyMsgId: replyMsgId ?? this.replyMsgId,
      replyPreview: replyPreview ?? this.replyPreview,
      replySenderName: replySenderName ?? this.replySenderName,
      readCount: readCount ?? this.readCount,
      localPath: localPath ?? this.localPath,
    );
  }
}
