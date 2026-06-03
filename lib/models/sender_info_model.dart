class SenderInfoModel {
  final int userId;
  final String nickname;
  final String avatar;
  final String? groupNickname;

  SenderInfoModel({
    required this.userId,
    required this.nickname,
    required this.avatar,
    this.groupNickname,
  });

  factory SenderInfoModel.fromJson(Map<String, dynamic> json) {
    return SenderInfoModel(
      userId: json['userId'] as int? ?? 0,
      nickname: json['nickname']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      groupNickname: json['groupNickname']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'nickname': nickname,
      'avatar': avatar,
      if (groupNickname != null) 'groupNickname': groupNickname,
    };
  }

  SenderInfoModel copyWith({
    int? userId,
    String? nickname,
    String? avatar,
    String? groupNickname,
  }) {
    return SenderInfoModel(
      userId: userId ?? this.userId,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      groupNickname: groupNickname ?? this.groupNickname,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SenderInfoModel &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          nickname == other.nickname &&
          avatar == other.avatar &&
          groupNickname == other.groupNickname;

  @override
  int get hashCode =>
      userId.hashCode ^
      nickname.hashCode ^
      avatar.hashCode ^
      (groupNickname?.hashCode ?? 0);

  @override
  String toString() {
    return 'SenderInfoModel{userId: $userId, nickname: $nickname, avatar: $avatar, groupNickname: $groupNickname}';
  }
}

class GroupInfoModel {
  final int groupId;
  final String groupName;
  final String? groupAvatar;

  GroupInfoModel({
    required this.groupId,
    required this.groupName,
    this.groupAvatar,
  });

  factory GroupInfoModel.fromJson(Map<String, dynamic> json) {
    return GroupInfoModel(
      groupId: json['groupId'] as int? ?? 0,
      groupName: json['groupName']?.toString() ?? '',
      groupAvatar: json['groupAvatar']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'groupName': groupName,
      if (groupAvatar != null) 'groupAvatar': groupAvatar,
    };
  }

  GroupInfoModel copyWith({
    int? groupId,
    String? groupName,
    String? groupAvatar,
  }) {
    return GroupInfoModel(
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      groupAvatar: groupAvatar ?? this.groupAvatar,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupInfoModel &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          groupName == other.groupName &&
          groupAvatar == other.groupAvatar;

  @override
  int get hashCode =>
      groupId.hashCode ^
      groupName.hashCode ^
      (groupAvatar?.hashCode ?? 0);

  @override
  String toString() {
    return 'GroupInfoModel{groupId: $groupId, groupName: $groupName, groupAvatar: $groupAvatar}';
  }
}
