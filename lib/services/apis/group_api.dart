import '../base_api.dart';

/// 群组相关 API 接口
///
/// 管理群组的创建、查询等操作
/// 所有接口对接 IM Server (IM服务器)
class GroupApi extends BaseApi {
  GroupApi();

  // ==================== 群组创建与查询 ====================

  /// 创建群组
  ///
  /// [ownerId] 群主用户 ID
  /// [name] 群组名称
  /// [memberIds] 初始成员 ID 列表
  ///
  /// 返回创建的群组信息，包含 id、name 等字段
  Future<Map<String, dynamic>> createGroup(int ownerId, String name, List<int> memberIds) async {
    final response = await postIm(
      '/group/create',
      queryParameters: {'ownerId': ownerId},
      data: {'name': name, 'memberIds': memberIds},
    );
    return extractData(response) as Map<String, dynamic>;
  }

  /// 获取当前用户的群组列表
  ///
  /// [userId] 当前用户的 ID
  ///
  /// 返回用户加入的群组列表数据
  Future<List<dynamic>> getUserGroups(int userId) async {
    final response = await getIm(
      '/group/list',
      queryParameters: {'userId': userId},
    );
    return extractList(response);
  }

  /// 获取群组详情信息
  ///
  /// [groupId] 群组 ID
  ///
  /// 返回群组详细信息，包含 id、name、成员列表等
  Future<Map<String, dynamic>> getGroupInfo(int groupId) async {
    final response = await getIm('/group/$groupId');
    return extractData(response) as Map<String, dynamic>;
  }
}
