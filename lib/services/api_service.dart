import 'apis/auth_api.dart';
import 'apis/user_api.dart';
import 'apis/contact_api.dart';

/// API 服务统一入口
///
/// 对外提供所有 HTTP API 的访问能力，内部按领域委托给对应的 Api 类：
/// - [authApi] - 认证相关（登录、注册）
/// - [userApi] - 用户资料（获取/修改个人信息）
/// - [contactApi] - 联系人/好友（好友列表、好友请求、搜索等）
///
/// 使用示例：
/// ```dart
/// final apiService = ApiService();
/// // 方式1：直接调用（向后兼容）
/// await apiService.login('username', 'password');
/// // 方式2：通过领域 API 调用（推荐，更清晰）
/// await apiService.authApi.login('username', 'password');
/// ```
class ApiService {
  // ==================== 领域 API 实例 ====================

  /// 认证相关 API（登录、注册）
  final AuthApi authApi = AuthApi();

  /// 用户资料相关 API
  final UserApi userApi = UserApi();

  /// 联系人/好友相关 API
  final ContactApi contactApi = ContactApi();

  // ==================== 向后兼容方法（委托给各领域 API）====================

  // ---------- 认证相关 ----------

  /// 用户登录（委托给 [AuthApi.login]）
  Future<Map<String, dynamic>> login(String username, String password) async {
    return authApi.login(username, password);
  }

  /// 用户注册（委托给 [AuthApi.register]）
  Future<Map<String, dynamic>> register(
    String username,
    String password,
    String nickname,
  ) async {
    return authApi.register(username, password, nickname);
  }

  // ---------- 用户资料相关 ----------

  /// 修改个人资料（委托给 [UserApi.updateProfile]）
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    return userApi.updateProfile(data);
  }

  /// 获取用户个人资料（委托给 [UserApi.getUserProfile]）
  Future<Map<String, dynamic>> getUserProfile() async {
    return userApi.getUserProfile();
  }

  // ---------- 联系人/好友相关 ----------

  /// 获取好友列表（委托给 [ContactApi.getFriendList]）
  Future<List<dynamic>> getFriendList(int userId) async {
    return contactApi.getFriendList(userId);
  }

  /// 发送好友请求（委托给 [ContactApi.sendFriendRequest]）
  Future<void> sendFriendRequest(int fromUserId, int toUserId) async {
    return contactApi.sendFriendRequest(fromUserId, toUserId);
  }

  /// 发送好友请求-字符串参数版本
  Future<void> sendFriendRequestWithString(String fromUserId, String toUserId) async {
    return contactApi.sendFriendRequestWithString(fromUserId, toUserId);
  }

  /// 接受好友请求（委托给 [ContactApi.acceptFriendRequest]）
  Future<void> acceptFriendRequest(int toUserId, int fromUserId) async {
    return contactApi.acceptFriendRequest(toUserId, fromUserId);
  }

  /// 接受好友请求-字符串参数版本
  Future<void> acceptFriendRequestWithString(String toUserId, String fromUserId) async {
    return contactApi.acceptFriendRequestWithString(toUserId, fromUserId);
  }

  /// 拒绝好友请求（委托给 [ContactApi.rejectFriendRequest]）
  Future<void> rejectFriendRequest(int toUserId, int fromUserId) async {
    return contactApi.rejectFriendRequest(toUserId, fromUserId);
  }

  /// 拒绝好友请求-字符串参数版本
  Future<void> rejectFriendRequestWithString(String toUserId, String fromUserId) async {
    return contactApi.rejectFriendRequestWithString(toUserId, fromUserId);
  }

  /// 删除好友（委托给 [ContactApi.deleteFriend]）
  Future<void> deleteFriend(int userId, int contactId) async {
    return contactApi.deleteFriend(userId, contactId);
  }

  /// 搜索用户（委托给 [ContactApi.searchUsers]）
  Future<List<dynamic>> searchUsers(String keyword) async {
    return contactApi.searchUsers(keyword);
  }

  /// 获取好友请求列表（委托给 [ContactApi.getFriendRequests]）
  Future<List<dynamic>> getFriendRequests(int userId) async {
    return contactApi.getFriendRequests(userId);
  }

  /// 检查好友状态（委托给 [ContactApi.checkFriendStatus]）
  Future<int> checkFriendStatus(int userId, int targetUserId) async {
    return contactApi.checkFriendStatus(userId, targetUserId);
  }
}
