import '../base_api.dart';

/// 把手机厂商令牌登记到 app-server，再由 app-server 转给 push-server。
class PushDeviceApi extends BaseApi {
  Future<Map<String, dynamic>> register({
    required String platform,
    required String provider,
    required String token,
    required String deviceId,
  }) {
    return postApp('/client/push/device', data: {
      'platform': platform,
      'provider': provider,
      'token': token,
      'deviceId': deviceId,
    });
  }

  Future<Map<String, dynamic>> unregister(String deviceId) {
    return deleteApp('/client/push/device', queryParameters: {
      'deviceId': deviceId,
    });
  }
}
