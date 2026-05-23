import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/user_model.dart';
import 'storage_service.dart';

class ApiService {
  static const String _appServerUrl = 'http://localhost:8080/api';
  static const String _imServerUrl = 'http://localhost:80/api';

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

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
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

  Future<UserModel> getUserInfo(String userId) async {
    try {
      await _attachToken(_appDio);
      final response = await _appDio.get('/user/info');
      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception('获取用户信息失败: ${e.message}');
    }
  }

  Future<List<dynamic>> getFriendList(int userId) async {
    try {
      await _attachToken(_imDio);
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
      await _attachToken(_imDio);
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
      await _attachToken(_imDio);
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
      await _attachToken(_imDio);
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
      await _attachToken(_imDio);
      await _imDio.delete('/friend/$friendId', queryParameters: {'userId': userId});
    } on DioException catch (e) {
      throw Exception('删除好友失败: ${e.message}');
    }
  }

  Future<List<dynamic>> searchUsers(String keyword, int userId) async {
    try {
      await _attachToken(_imDio);
      final response = await _imDio.get('/friend/search-users', queryParameters: {
        'keyword': keyword,
        'userId': userId,
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
      await _attachToken(_imDio);
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
}
