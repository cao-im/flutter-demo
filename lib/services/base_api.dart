import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:cao_im_sdk_flutter/utils/network_log_interceptor.dart';
import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart' show NetworkLogInterceptor;
import '../services/storage_service.dart';

/// API 基础封装类
///
/// 提供统一的 HTTP 请求能力，包括：
/// - App Server (应用服务器) 的 Dio 实例
/// - IM Server (IM服务器) 的 Dio 实例
/// - 通用的请求封装方法（自动处理 Token、错误处理、响应解析）
///
/// 使用方式：各领域 API 类继承此类，直接使用封装好的请求方法
abstract class BaseApi {
  /// App Server 基础地址（认证、用户资料等）
  static const String appServerUrl = 'http://192.168.0.138:8081/api';

  /// IM Server 基础地址（联系人、好友、群组等）
  static const String imServerUrl = 'http://192.168.0.138:8080/api';

  /// 连接超时时间（秒）
  static const int connectTimeoutSeconds = 10;

  /// 接收超时时间（秒）
  static const int receiveTimeoutSeconds = 10;

  late final Dio _appDio;
  late final Dio _imDio;

  BaseApi() {
    _appDio = _createAppDio();
    _imDio = _createImDio();
  }

  /// 获取 App Server 的 Dio 实例（用于认证、用户资料等接口）
  Dio get appDio => _appDio;

  /// 获取 IM Server 的 Dio 实例（用于联系人、好友、群组等接口）
  Dio get imDio => _imDio;

  // ==================== Dio 实例创建 ====================

  /// 创建 App Server 的 Dio 实例
  ///
  /// 自动携带 App 端 Token（Authorization: Bearer xxx）
  /// 401 时打印警告日志
  Dio _createAppDio() {
    final dio = Dio(BaseOptions(
      baseUrl: appServerUrl,
      connectTimeout: const Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: receiveTimeoutSeconds),
      headers: {'Content-Type': 'application/json'},
      responseType: ResponseType.plain,
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await StorageService.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        if (e.response?.statusCode == 401) {
          debugPrint('⚠️[BaseApi] App API 返回401，Token可能已过期');
        }
        handler.next(e);
      },
    ));

    dio.interceptors.add(NetworkLogInterceptor());

    return dio;
  }

  /// 创建 IM Server 的 Dio 实例
  ///
  /// 自动携带 IM Token（Authorization: Bearer xxx）
  Dio _createImDio() {
    final dio = Dio(BaseOptions(
      baseUrl: imServerUrl,
      connectTimeout: const Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: receiveTimeoutSeconds),
      headers: {'Content-Type': 'application/json'},
      responseType: ResponseType.plain,
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final imToken = await StorageService.getImToken();
        if (imToken != null && imToken.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $imToken';
        }
        handler.next(options);
      },
    ));

    dio.interceptors.add(NetworkLogInterceptor());

    return dio;
  }

  // ==================== 响应解析 ====================

  /// 解析服务端响应数据
  ///
  /// 支持字符串和 Map 两种格式，自动 JSON 解析
  dynamic _parseResponse(dynamic responseData) {
    if (responseData is String) {
      try {
        return jsonDecode(responseData);
      } catch (e) {
        debugPrint('JSON 解析失败: $e');
        debugPrint('原始响应数据: $responseData');
        throw Exception('服务器响应格式错误');
      }
    }
    return responseData;
  }

  // ==================== 通用请求方法 ====================

  /// 发送 GET 请求到 App Server
  ///
  /// [path] 接口路径（如 '/user/info'）
  /// [queryParameters] 查询参数
  /// 返回解析后的 Map 数据
  Future<Map<String, dynamic>> getApp(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final response = await _appDio.get(path, queryParameters: queryParameters);
      final data = _parseResponse(response.data);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('请求失败: ${e.message}');
    }
  }

  /// 发送 POST 请求到 App Server
  ///
  /// [path] 接口路径（如 '/client/login'）
  /// [data] 请求体数据
  /// [removeAuth] 是否移除 Authorization 头（登录/注册接口需要）
  Future<Map<String, dynamic>> postApp(String path, {dynamic data, bool removeAuth = false}) async {
    try {
      if (removeAuth) {
        _appDio.options.headers.remove('Authorization');
      }
      final response = await _appDio.post(path, data: data);
      final parsed = _parseResponse(response.data);
      return parsed as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('请求失败: ${e.message}');
    }
  }

  /// 发送 PUT 请求到 App Server
  Future<Map<String, dynamic>> putApp(String path, {dynamic data}) async {
    try {
      final response = await _appDio.put(path, data: data);
      final parsed = _parseResponse(response.data);
      return parsed as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('请求失败: ${e.message}');
    }
  }

  /// 发送 DELETE 请求到 App Server
  Future<Map<String, dynamic>> deleteApp(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final response = await _appDio.delete(path, queryParameters: queryParameters);
      final parsed = _parseResponse(response.data);
      return parsed as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('请求失败: ${e.message}');
    }
  }

  /// 发送 GET 请求到 IM Server
  Future<Map<String, dynamic>> getIm(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final response = await _imDio.get(path, queryParameters: queryParameters);
      final data = _parseResponse(response.data);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('请求失败: ${e.message}');
    }
  }

  /// 发送 POST 请求到 IM Server
  Future<Map<String, dynamic>> postIm(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    try {
      final response = await _imDio.post(path, data: data, queryParameters: queryParameters);
      final parsed = _parseResponse(response.data);
      return parsed as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('请求失败: ${e.message}');
    }
  }

  /// 发送 PUT 请求到 IM Server
  Future<void> putIm(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      await _imDio.put(path, queryParameters: queryParameters);
    } on DioException catch (e) {
      throw Exception('请求失败: ${e.message}');
    }
  }

  /// 发送 DELETE 请求到 IM Server
  Future<void> deleteIm(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      await _imDio.delete(path, queryParameters: queryParameters);
    } on DioException catch (e) {
      throw Exception('请求失败: ${e.message}');
    }
  }

  /// 从响应中提取 data 字段列表
  ///
  /// 用于返回列表数据的接口，自动提取 response.data.data 并转为 List
  List<dynamic> extractList(Map<String, dynamic> response) {
    if (response.containsKey('data')) {
      final data = response['data'];
      if (data is List) return data;
    }
    return [];
  }

  /// 从响应中提取单个 data 字段
  dynamic extractData(Map<String, dynamic> response) {
    return response['data'];
  }

  /// 从响应中提取 code 字段
  int? extractCode(Map<String, dynamic> response) {
    return response['code'] as int?;
  }

  /// 从响应中提取 message 字段
  String? extractMessage(Map<String, dynamic> response) {
    return response['message'] as String?;
  }
}
