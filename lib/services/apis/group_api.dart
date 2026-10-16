import 'dart:convert';

import 'package:dio/dio.dart';

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
    _ensureOk(response);
    return extractData(response) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchMembers(int groupId) async {
    Object? viewError;
    try {
      final response = await getIm('/group/$groupId/member-views');
      _ensureOk(response);
      final views = _asMaps(extractList(response));
      if (views.isNotEmpty) return views;
    } catch (e) {
      viewError = e;
    }
    try {
      final response = await getIm('/group/$groupId/members');
      _ensureOk(response);
      return _asMaps(extractList(response)).map((row) {
        return {
          'userId': row['userId'],
          'role': row['role'] ?? 0,
          'mute': row['mute'] == true || row['mute'] == 1,
          'nickname': '',
          'groupNickname': row['nickname']?.toString() ?? '',
          'avatar': row['avatar']?.toString() ?? '',
          'memberId': row['id'],
          'joinTime': row['joinTime'],
        };
      }).toList();
    } catch (e) {
      throw viewError ?? e;
    }
  }

  Future<void> updateMyNickname(int groupId, String nickname) {
    return _mutate('/group/$groupId/my-nickname', queryParameters: {'nickname': nickname});
  }

  Future<void> updateName(int groupId, String name) {
    return _mutate('/group/$groupId', queryParameters: {'name': name});
  }

  List<Map<String, dynamic>> _asMaps(List<dynamic> raw) {
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<dynamic>> memberViews(int groupId) async {
    final response = await getIm('/group/$groupId/member-views');
    _ensureOk(response);
    return extractList(response);
  }

  Future<List<dynamic>> joinRequests(int groupId) async {
    final response = await getIm('/group/$groupId/join-requests');
    _ensureOk(response);
    return extractList(response);
  }

  Future<String> addMember(int groupId, int userId) async {
    final response = await postIm(
      '/group/$groupId/member',
      queryParameters: {'userId': userId},
    );
    _ensureOk(response);
    return extractData(response)?.toString() ?? 'joined';
  }

  Future<void> removeMember(int groupId, int userId) {
    return _mutate('/group/$groupId/member/$userId', method: 'DELETE');
  }

  Future<void> updateSettings(
    int groupId, {
    String? introduction,
    int? joinType,
    int? muteAll,
  }) {
    return _mutate(
      '/group/$groupId/settings',
      queryParameters: {
        if (introduction != null) 'introduction': introduction,
        if (joinType != null) 'joinType': joinType,
        if (muteAll != null) 'muteAll': muteAll,
      },
    );
  }

  Future<void> setMemberRole(int groupId, int userId, int role) {
    return _mutate(
      '/group/$groupId/member/$userId/role',
      queryParameters: {'role': role},
    );
  }

  Future<void> setMemberMute(int groupId, int userId, bool mute) {
    return _mutate(
      '/group/$groupId/member/$userId/mute',
      queryParameters: {'mute': mute ? 1 : 0},
    );
  }

  Future<void> reviewJoin(int groupId, int requestId, bool accept) {
    return _mutate(
      '/group/$groupId/join-requests/$requestId/review',
      method: 'POST',
      queryParameters: {'accept': accept},
    );
  }

  void _ensureOk(Map<String, dynamic> response) {
    final code = response['code'];
    if (code != null && code != 200) {
      throw Exception(response['message']?.toString() ?? '操作失败');
    }
  }

  Future<void> _mutate(
    String path, {
    String method = 'PUT',
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final Response<dynamic> response;
      if (method == 'DELETE') {
        response = await imDio.delete(path, queryParameters: queryParameters);
      } else if (method == 'POST') {
        response = await imDio.post(path, queryParameters: queryParameters);
      } else {
        response = await imDio.put(path, queryParameters: queryParameters);
      }
      final raw = response.data;
      final parsed = raw is String ? jsonDecode(raw) : raw;
      if (parsed is Map<String, dynamic>) {
        _ensureOk(parsed);
      } else if (parsed is Map) {
        _ensureOk(Map<String, dynamic>.from(parsed));
      }
    } on DioException catch (e) {
      throw Exception(e.message ?? '请求失败');
    }
  }
}
