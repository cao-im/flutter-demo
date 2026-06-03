import 'message_model.dart';
import 'user_model.dart';

class ConversationModel {
  final String id;
  final int? dbId;
  final int targetId;
  final String name;
  final String? avatar;
  final List<String> participantIds;
  final MessageModel? lastMessage;
  final int unreadCount;
  final DateTime? lastActiveTime;
  final bool isGroup;
  final String? groupOwner;

  ConversationModel({
    required this.id,
    this.dbId,
    required this.targetId,
    required this.name,
    this.avatar,
    required this.participantIds,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastActiveTime,
    this.isGroup = false,
    this.groupOwner,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] ?? '',
      targetId: json['target_id'] ?? 0,
      name: json['name'] ?? '',
      avatar: json['avatar'],
      participantIds: List<String>.from(json['participant_ids'] ?? []),
      lastMessage: json['last_message'] != null
          ? MessageModel.fromJson(json['last_message'])
          : null,
      unreadCount: json['unread_count'] ?? 0,
      lastActiveTime: json['last_active_time'] != null
          ? DateTime.parse(json['last_active_time'])
          : null,
      isGroup: json['is_group'] ?? false,
      groupOwner: json['group_owner'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'target_id': targetId,
      'name': name,
      'avatar': avatar,
      'participant_ids': participantIds,
      'last_message': lastMessage?.toJson(),
      'unread_count': unreadCount,
      'last_active_time': lastActiveTime?.toIso8601String(),
      'is_group': isGroup,
      'group_owner': groupOwner,
    };
  }

  ConversationModel copyWith({
    String? id,
    int? dbId,
    int? targetId,
    String? name,
    String? avatar,
    List<String>? participantIds,
    MessageModel? lastMessage,
    int? unreadCount,
    DateTime? lastActiveTime,
    bool? isGroup,
    String? groupOwner,
  }) {
    return ConversationModel(
      id: id ?? this.id,
      dbId: dbId ?? this.dbId,
      targetId: targetId ?? this.targetId,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      participantIds: participantIds ?? this.participantIds,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      lastActiveTime: lastActiveTime ?? this.lastActiveTime,
      isGroup: isGroup ?? this.isGroup,
      groupOwner: groupOwner ?? this.groupOwner,
    );
  }
}

class ChatModel {
  final String currentConversationId;
  final List<MessageModel> messages;
  final bool isLoading;
  final bool isConnected;

  ChatModel({
    this.currentConversationId = '',
    this.messages = const [],
    this.isLoading = false,
    this.isConnected = false,
  });
}
