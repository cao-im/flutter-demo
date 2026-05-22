import 'message_model.dart';
import 'user_model.dart';

class ConversationModel {
  final String id;
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
