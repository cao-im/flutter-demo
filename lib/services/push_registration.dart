import 'package:flutter/foundation.dart';

import 'apis/push_device_api.dart';
import 'storage_service.dart';

/// 登录后把已拿到的厂商令牌登记到推送服务。还没有厂商 SDK 时直接返回。
class PushRegistration {
  static final PushDeviceApi _api = PushDeviceApi();

  static Future<void> updateToken({
    required String provider,
    required String token,
  }) async {
    await StorageService.savePushProvider(provider);
    await StorageService.savePushToken(token);
    await sync();
  }

  static Future<void> sync() async {
    final platform = _mobilePlatform();
    final token = await StorageService.getPushToken();
    final provider = await StorageService.getPushProvider();
    if (platform == null || token == null || token.isEmpty || provider == null || provider.isEmpty) {
      return;
    }
    try {
      final deviceId = await StorageService.pushDeviceId();
      await _api.register(
        platform: platform,
        provider: provider,
        token: token,
        deviceId: deviceId,
      );
    } catch (e) {
      debugPrint('推送设备登记失败: $e');
    }
  }

  static Future<void> unregister() async {
    final deviceId = await StorageService.getPushDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      return;
    }
    try {
      await _api.unregister(deviceId);
    } catch (e) {
      debugPrint('推送设备注销失败: $e');
    }
  }

  static String? _mobilePlatform() {
    if (kIsWeb) {
      return null;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return null;
    }
  }
}
