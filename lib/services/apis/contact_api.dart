import 'package:flutter/foundation.dart';
import '../base_api.dart';

/// 联系人/好友相关 API 接口
///
/// 管理联系人列表、好友请求、搜索用户等操作
/// 所有接口对接 IM Server (IM服务器)
class ContactApi extends BaseApi {
  ContactApi();

  // ==================== 好友列表相关 ====================

  /// 获取好友列表
  ///
  /// [userId] 当前用户的 ID
  ///
  /// 返回好友列表数据，每项包含好友的基本信息
  Future<List<dynamic>> getFriendList(int userId) async {
    final response = await getIm(
      '/contact/list',
      queryParameters: {'userId': userId},
    );
    return extractList(response);
  }

  /// 搜索用户
  ///
  /// [keyword] 搜索关键词（用户名/昵称）
  ///
  /// 返回匹配的用户列表
  Future<List<dynamic>> searchUsers(String keyword) async {
    final response = await getIm(
      '/contact/search-users',
      queryParameters: {'keyword': keyword},
    );
    return extractList(response);
  }

  /// 检查与目标用户的好友关系状态
  ///
  /// [userId] 当前用户 ID
  /// [targetUserId] 目标用户 ID
  ///
  /// 返回状态码：0=非好友，1=已是好友
  Future<int> checkFriendStatus(int userId, int targetUserId) async {
    try {
      final response = await getIm(
        '/contact/check-status',
        queryParameters: {'userId': userId, 'targetUserId': targetUserId},
      );
      final data = extractData(response);
      return data as int? ?? 0;
    } catch (e) {
      debugPrint('检查好友状态失败: $e');
      return 0;
    }
  }

  /// 删除好友
  ///
  /// [userId] 当前用户 ID
  /// [contactId] 要删除的好友 ID
  Future<void> deleteFriend(int userId, int contactId) async {
    await deleteIm(
      '/contact/$contactId',
      queryParameters: {'userId': userId},
    );
  }

  // ==================== 好友请求相关 ====================

  /// 发送好友请求
  ///
  /// [fromUserId] 发送者用户 ID
  /// [toUserId] 接收者用户 ID
  Future<void> sendFriendRequest(int fromUserId, int toUserId) async {
    await postIm(
      '/friend-request/request',
      queryParameters: {'fromUserId': fromUserId, 'toUserId': toUserId},
    );
  }

  /// 发送好友请求（字符串参数版本）
  ///
  /// 当用户 ID 为字符串类型时使用此方法
  Future<void> sendFriendRequestWithString(String fromUserId, String toUserId) async {
    await postIm(
      '/friend-request/request',
      queryParameters: {'fromUserId': fromUserId, 'toUserId': toUserId},
    );
  }

  /// 获取待处理的好友请求列表
  ///
  /// [userId] 当前用户 ID
  ///
  /// 返回好友请求数据列表
  Future<List<dynamic>> getFriendRequests(int userId) async {
    final response = await getIm(
      '/friend-request/pending',
      queryParameters: {'userId': userId},
    );
    return extractList(response);
  }

  /// 接受好友请求
  ///
  /// [toUserId] 当前用户 ID（接收方）
  /// [fromUserId] 请求发起者 ID
  Future<void> acceptFriendRequest(int toUserId, int fromUserId) async {
    await putIm(
      '/friend-request/accept',
      queryParameters: {'toUserId': toUserId, 'fromUserId': fromUserId},
    );
  }

  /// 接受好友请求（字符串参数版本）
  Future<void> acceptFriendRequestWithString(String toUserId, String fromUserId) async {
    await putIm(
      '/friend-request/accept',
      queryParameters: {'toUserId': toUserId, 'fromUserId': fromUserId},
    );
  }

  /// 拒绝好友请求
  ///
  /// [toUserId] 当前用户 ID（接收方）
  /// [fromUserId] 请求发起者 ID
  Future<void> rejectFriendRequest(int toUserId, int fromUserId) async {
    await putIm(
      '/friend-request/reject',
      queryParameters: {'toUserId': toUserId, 'fromUserId': fromUserId},
    );
  }

  /// 拒绝好友请求（字符串参数版本）
  Future<void> rejectFriendRequestWithString(String toUserId, String fromUserId) async {
    await putIm(
      '/friend-request/reject',
      queryParameters: {'toUserId': toUserId, 'fromUserId': fromUserId},
    );
  }
}
