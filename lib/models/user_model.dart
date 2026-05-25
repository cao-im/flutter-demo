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
  });

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
    );
  }
}
