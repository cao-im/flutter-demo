import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../base_api.dart';

class FileApi extends BaseApi {
  FileApi();

  /// 上传文件并返回可访问的 URL。
  Future<String> uploadBytes(Uint8List bytes, String filename) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await appDio.post(
      '/file/upload',
      data: formData,
      options: Options(
        contentType: Headers.multipartFormDataContentType,
        headers: {Headers.contentTypeHeader: Headers.multipartFormDataContentType},
      ),
    );
    final dynamic body = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (body is! Map) {
      throw Exception('上传响应格式错误');
    }
    final data = body['data'];
    if (data is Map && data['url'] is String && (data['url'] as String).isNotEmpty) {
      return data['url'] as String;
    }
    throw Exception(body['message']?.toString() ?? '上传失败');
  }
}
