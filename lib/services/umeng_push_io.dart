import 'package:flutter/foundation.dart';
import 'package:umeng_common_sdk/umeng_common_sdk.dart';
import 'package:umeng_push_sdk/umeng_push_sdk.dart';

import 'push_registration.dart';

const _androidAppKey = String.fromEnvironment('UMENG_ANDROID_APPKEY');
const _iosAppKey = String.fromEnvironment('UMENG_IOS_APPKEY');
const _messageSecret = String.fromEnvironment('UMENG_MESSAGE_SECRET');
const _channel = String.fromEnvironment('UMENG_CHANNEL', defaultValue: 'caoim');

Future<void> startUmengPush() async {
  if (kIsWeb) {
    return;
  }
  final mobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (!mobile || _androidAppKey.isEmpty || _iosAppKey.isEmpty || _messageSecret.isEmpty) {
    return;
  }
  try {
    UmengPushSdk.setTokenCallback((token) {
      final text = token.trim();
      if (text.isEmpty) {
        return;
      }
      PushRegistration.updateToken(provider: 'umeng', token: text);
    });
    await UmengCommonSdk.initCommon(_androidAppKey, _iosAppKey, _channel, _messageSecret);
    await UmengPushSdk.register(_iosAppKey, _channel);
    final existing = await UmengPushSdk.getRegisteredId();
    if (existing != null && existing.trim().isNotEmpty) {
      await PushRegistration.updateToken(provider: 'umeng', token: existing.trim());
    }
  } catch (e) {
    debugPrint('友盟推送初始化失败: $e');
  }
}
