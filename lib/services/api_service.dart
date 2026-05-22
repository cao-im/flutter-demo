import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/user_model.dart';
import 'storage_service.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8080/api';
  late Dio _dio;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await StorageService.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          StorageService.removeToken();
        }
        return handler.next(error);
      },
    ));
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await _dio.post('/client/login', data: {
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
      final response = await _dio.post('/client/register', data: {
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
      final response = await _dio.get('/user/info');
      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception('获取用户信息失败: ${e.message}');
    }
  }

  Future<List<dynamic>> getConversations() async {
    try {
      final response = await _dio.get('/conversations');
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw Exception('获取会话列表失败: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> createConversation(
      String name, List<String> participantIds, bool isGroup) async {
    try {
      final response = await _dio.post('/conversations', data: {
        'name': name,
        'participant_ids': participantIds,
        'is_group': isGroup,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('创建会话失败: ${e.message}');
    }
  }

  Future<List<dynamic>> getMessages(String conversationId) async {
    try {
      final response = await _dio.get('/conversations/$conversationId/messages');
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw Exception('获取消息失败: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> sendMessage(
      String conversationId, String content, String type) async {
    try {
      final response = await _dio.post(
        '/conversations/$conversationId/messages',
        data: {
          'content': content,
          'type': type,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('发送消息失败: ${e.message}');
    }
  }

  Future<List<dynamic>> getContacts() async {
    try {
      final response = await _dio.get('/contacts');
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw Exception('获取联系人失败: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> searchUsers(String keyword) async {
    try {
      final response = await _dio.get('/users/search?keyword=$keyword');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('搜索用户失败: ${e.message}');
    }
  }
}
