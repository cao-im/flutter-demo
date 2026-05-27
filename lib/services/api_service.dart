import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'storage_service.dart';

class ApiService {
  static const String _appServerUrl = 'http://192.168.0.138:8081/api';
  static const String _imServerUrl = 'http://192.168.0.138:8080/api';

  late final Dio _appDio;
  late final Dio _imDio;

  ApiService() {
    _appDio = _createDio(_appServerUrl);
    _imDio = _createDio(_imServerUrl);
  }

  Dio _createDio(String baseUrl) {
    return Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));
  }

  Future<void> _attachToken(Dio dio) async {
    final token = await StorageService.getToken();
    if (token != null && token.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<void> _attachImToken(Dio dio) async {
    final token = await StorageService.getImToken();
    if (token != null && token.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      final appToken = await StorageService.getToken();
      if (appToken != null && appToken.isNotEmpty) {
        dio.options.headers['Authorization'] = 'Bearer $appToken';
      }
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      _appDio.options.headers.remove('Authorization');
      final response = await _appDio.post('/client/login', data: {
        'username': username,
        'password': password,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('登录失败: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> register(
      String username, String password, String nickname) async {
    try {
      _appDio.options.headers.remove('Authorization');
      final response = await _appDio.post('/client/register', data: {
        'username': username,
        'password': password,
        'nickname': nickname,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('注册失败: ${e.message}');
    }
  }

  Future<UserModel> getUserInfo() async {
    try {
      await _attachImToken(_imDio);
      final response = await _imDio.get('/user/info');
      final data = response.data;
      
      if (data is Map<String, dynamic>) {
        final userData = data['data'];
        if (userData != null && userData is Map<String, dynamic>) {
          return UserModel.fromJson(userData);
        }
      }
      
      throw Exception('用户信息响应格式错误');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Token无效或已过期');
      }
      throw Exception('获取用户信息失败: ${e.message}');
    }
  }

  Future<List<dynamic>> getFriendList(int userId) async {
    try {
      await _attachImToken(_imDio);
      final response = await _imDio.get('/friend/list', queryParameters: {'userId': userId});
      final data = response.data;
      if (data is Map<String, dynamic> && data.containsKey('data')) {
        return data['data'] as List<dynamic>;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('获取好友列表失败: ${e.message}');
    }
  }

  Future<void> sendFriendRequest(int userId, int friendId) async {
    try {
      await _attachImToken(_imDio);
      await _imDio.post('/friend/request', queryParameters: {
        'userId': userId,
        'friendId': friendId,
      });
    } on DioException catch (e) {
      throw Exception('发送好友请求失败: ${e.message}');
    }
  }

  Future<void> sendFriendRequestWithString(String userId, String friendId) async {
    try {
      await _attachImToken(_imDio);
      await _imDio.post('/friend/request', queryParameters: {
        'userId': userId,
        'friendId': friendId,
      });
    } on DioException catch (e) {
      throw Exception('发送好友请求失败: ${e.message}');
    }
  }

  Future<void> acceptFriendRequest(int userId, int friendId) async {
    try {
      await _attachImToken(_imDio);
      await _imDio.put('/friend/accept', queryParameters: {
        'userId': userId,
        'friendId': friendId,
      });
    } on DioException catch (e) {
      throw Exception('接受好友请求失败: ${e.message}');
    }
  }

  Future<void> acceptFriendRequestWithString(String userId, String friendId) async {
    try {
      await _attachImToken(_imDio);
      await _imDio.put('/friend/accept', queryParameters: {
        'userId': userId,
        'friendId': friendId,
      });
    } on DioException catch (e) {
      throw Exception('接受好友请求失败: ${e.message}');
    }
  }

  Future<void> rejectFriendRequest(int userId, int friendId) async {
    try {
      await _attachImToken(_imDio);
      await _imDio.put('/friend/reject', queryParameters: {
        'userId': userId,
        'friendId': friendId,
      });
    } on DioException catch (e) {
      throw Exception('拒绝好友请求失败: ${e.message}');
    }
  }

  Future<void> rejectFriendRequestWithString(String userId, String friendId) async {
    try {
      await _attachImToken(_imDio);
      await _imDio.put('/friend/reject', queryParameters: {
        'userId': userId,
        'friendId': friendId,
      });
    } on DioException catch (e) {
      throw Exception('拒绝好友请求失败: ${e.message}');
    }
  }

  Future<void> deleteFriend(int userId, int friendId) async {
    try {
      await _attachImToken(_imDio);
      await _imDio.delete('/friend/$friendId', queryParameters: {'userId': userId});
    } on DioException catch (e) {
      throw Exception('删除好友失败: ${e.message}');
    }
  }

  Future<List<dynamic>> searchUsers(String keyword) async {
    try {
      await _attachImToken(_imDio);
      final response = await _imDio.get('/friend/search-users', queryParameters: {
        'keyword': keyword,
      });
      final data = response.data;
      if (data is Map<String, dynamic> && data.containsKey('data')) {
        return data['data'] as List<dynamic>;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('搜索用户失败: ${e.message}');
    }
  }

  Future<List<dynamic>> getFriendRequests(int userId) async {
    try {
      await _attachImToken(_imDio);
      final response = await _imDio.get('/friend/requests', queryParameters: {'userId': userId});
      final data = response.data;
      if (data is Map<String, dynamic> && data.containsKey('data')) {
        return data['data'] as List<dynamic>;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('获取好友请求失败: ${e.message}');
    }
  }

  Future<int> checkFriendStatus(int userId, int friendId) async {
    try {
      await _attachImToken(_imDio);
      final response = await _imDio.get('/friend/check-status', queryParameters: {
        'userId': userId,
        'friendId': friendId,
      });
      final data = response.data;
      if (data is Map<String, dynamic> && data.containsKey('data')) {
        return data['data'] as int ?? 0;
      }
      return 0;
    } on DioException catch (e) {
      debugPrint('检查好友状态失败: $e');
      return 0;
    }
  }
}
