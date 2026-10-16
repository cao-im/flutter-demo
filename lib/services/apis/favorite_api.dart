import 'dart:convert';

import 'package:dio/dio.dart';

import '../base_api.dart';

class FavoriteApi extends BaseApi {
  FavoriteApi();

  Future<Map<String, dynamic>> add(int mid) async {
    final response = await postIm('/favorite', queryParameters: {'mid': mid});
    _ensureOk(response);
    final data = extractData(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<List<Map<String, dynamic>>> list() async {
    final response = await getIm('/favorite');
    _ensureOk(response);
    return extractList(response).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<void> remove(int id) async {
    try {
      final response = await imDio.delete('/favorite/$id');
      final raw = response.data;
      final parsed = raw is String ? jsonDecode(raw) : raw;
      if (parsed is Map) {
        _ensureOk(Map<String, dynamic>.from(parsed));
      }
    } on DioException catch (error) {
      throw Exception(error.message ?? '请求失败');
    }
  }

  void _ensureOk(Map<String, dynamic> response) {
    final code = response['code'];
    if (code != null && code != 200) {
      throw Exception(response['message']?.toString() ?? '操作失败');
    }
  }
}
