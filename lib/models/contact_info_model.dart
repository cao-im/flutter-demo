class ContactInfo {
  final int id;
  final int userId;
  final String username;
  final String nickname;
  final String avatar;
  final String remark;
  final bool isTop;
  final bool isMute;

  ContactInfo({
    required this.id,
    required this.userId,
    required this.username,
    required this.nickname,
    required this.avatar,
    this.remark = '',
    this.isTop = false,
    this.isMute = false,
  });

  factory ContactInfo.fromJson(Map<String, dynamic> json) {
    return ContactInfo(
      id: json['id'] as int? ?? 0,
      userId: json['contactUserId'] as int? ?? json['userId'] as int? ?? json['id'] as int? ?? 0,
      username: json['username']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      remark: json['remark']?.toString() ?? '',
      isTop: json['isTop'] == true || json['isTop'] == 1,
      isMute: json['isMute'] == true || json['isMute'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'username': username,
      'nickname': nickname,
      'avatar': avatar,
      'remark': remark,
      'isTop': isTop,
      'isMute': isMute,
    };
  }

  ContactInfo copyWith({
    int? id,
    int? userId,
    String? username,
    String? nickname,
    String? avatar,
    String? remark,
    bool? isTop,
    bool? isMute,
  }) {
    return ContactInfo(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      remark: remark ?? this.remark,
      isTop: isTop ?? this.isTop,
      isMute: isMute ?? this.isMute,
    );
  }

  @override
  String toString() {
    return 'ContactInfo(id: $id, userId: $userId, username: $username, nickname: $nickname, avatar: $avatar, remark: $remark)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContactInfo && other.userId == userId;
  }

  @override
  int get hashCode => userId.hashCode;
}
