class UserModel {
  final String id;
  final String username;
  final String nickname;
  final String? avatar;
  final String? email;
  final String? phone;
  final DateTime? createdAt;
  final bool isOnline;
  final String? imUserId;
  final int friendStatus;
  /// 备注名（优先于昵称展示）
  final String remark;
  /// 联系人维度置顶（同步到私聊会话）
  final bool isTop;
  /// 联系人维度免打扰（同步到私聊会话）
  final bool isMute;

  UserModel({
    required this.id,
    required this.username,
    required this.nickname,
    this.avatar,
    this.email,
    this.phone,
    this.createdAt,
    this.isOnline = false,
    this.imUserId,
    this.friendStatus = 0,
    this.remark = '',
    this.isTop = false,
    this.isMute = false,
  });

  /// 展示名：备注 > 昵称 > 用户名
  String get displayName {
    if (remark.isNotEmpty) return remark;
    if (nickname.isNotEmpty) return nickname;
    return username;
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? json['username']?.toString() ?? '',
      avatar: json['avatar'],
      email: json['email'],
      phone: json['phone'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      isOnline: json['is_online'] ?? false,
      imUserId: json['im_user_id']?.toString() ?? json['imUserId']?.toString(),
      friendStatus: json['friend_status'] ?? json['friendStatus'] ?? 0,
      remark: json['remark']?.toString() ?? '',
      isTop: json['isTop'] == true ||
          json['isTop'] == 1 ||
          json['is_top'] == true ||
          json['is_top'] == 1,
      isMute: json['isMute'] == true ||
          json['isMute'] == 1 ||
          json['is_mute'] == true ||
          json['is_mute'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'nickname': nickname,
      'avatar': avatar,
      'email': email,
      'phone': phone,
      'created_at': createdAt?.toIso8601String(),
      'is_online': isOnline,
      'im_user_id': imUserId,
      'friend_status': friendStatus,
      'remark': remark,
      'isTop': isTop,
      'isMute': isMute,
    };
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? nickname,
    String? avatar,
    String? email,
    String? phone,
    DateTime? createdAt,
    bool? isOnline,
    String? imUserId,
    int? friendStatus,
    String? remark,
    bool? isTop,
    bool? isMute,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      isOnline: isOnline ?? this.isOnline,
      imUserId: imUserId ?? this.imUserId,
      friendStatus: friendStatus ?? this.friendStatus,
      remark: remark ?? this.remark,
      isTop: isTop ?? this.isTop,
      isMute: isMute ?? this.isMute,
    );
  }
}
