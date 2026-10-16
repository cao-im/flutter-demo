import '../base_api.dart';

class MessageApi extends BaseApi {
  MessageApi();

  Future<Map<int, int>> groupReadCounts(int groupId, List<int> mids) async {
    if (groupId <= 0 || mids.isEmpty) return {};
    final response = await getIm(
      '/message/group/$groupId/read-counts',
      queryParameters: {'mids': mids.take(50).join(',')},
    );
    return _counts(response);
  }

  Future<Map<int, int>> privateReadCounts(int peerId, List<int> mids) async {
    if (peerId <= 0 || mids.isEmpty) return {};
    final response = await getIm(
      '/message/private/$peerId/read-counts',
      queryParameters: {'mids': mids.take(50).join(',')},
    );
    return _counts(response);
  }

  Map<int, int> _counts(Map<String, dynamic> response) {
    final code = response['code'];
    if (code != null && code != 200) {
      throw Exception(response['message']?.toString() ?? '查询已读状态失败');
    }
    final data = extractData(response);
    if (data is! Map) return {};
    final counts = <int, int>{};
    data.forEach((key, value) {
      final mid = int.tryParse('$key');
      final count = value is int ? value : int.tryParse('$value');
      if (mid != null && mid > 0 && count != null && count >= 0) {
        counts[mid] = count;
      }
    });
    return counts;
  }
}