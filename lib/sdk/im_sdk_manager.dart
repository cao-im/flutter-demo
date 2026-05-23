import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart';

class IMSdkManager {
  static final IMSdkManager _instance = IMSdkManager._internal();
  factory IMSdkManager() => _instance;
  IMSdkManager._internal();

  IMClient get client => IMClient.instance;
  bool get isInitialized => _isInitialized;
  bool get isConnected => client.isConnected;

  bool _isInitialized = false;

  Future<void> initialize({required String serverUrl}) async {
    if (_isInitialized) {
      print('⚠️[SdkManager] 已初始化，跳过');
      return;
    }

    print('📍[SdkManager] ====== initialize() 开始 ======');
    print('📍[SdkManager] serverUrl: $serverUrl');

    try {
      print('📍[SdkManager] 调用 IMClient.init()...');
      await client.init(serverUrl: serverUrl);
      print('✅[SdkManager] IMClient.init() 成功');
      _isInitialized = true;
    } catch (e, stack) {
      print('❌[SdkManager] IMClient.init() 失败: $e');
      print('❌[SdkManager] stackTrace: $stack');
      rethrow;
    }

    print('📍[SdkManager] ====== initialize() 结束 ======');
  }

  Future<void> connect(String token, {int? userId}) async {
    if (!_isInitialized) {
      print('⚠️[SdkManager] SDK 未初始化');
      throw Exception('SDK 未初始化，请先调用 initialize');
    }

    print('');
    print('📍[SdkManager] ====== connect() 开始 ======');
    print('📍[SdkManager] token前20字符: ${token.substring(0, token.length > 20 ? 20 : token.length)}...');
    print('📍[SdkManager] userId: $userId');

    try {
      print('📍[SdkManager] 调用 IMClient.connect(token, userId: $userId)...');
      await client.connect(token, userId: userId);
      print('✅[SdkManager] IMClient.connect() 返回成功');
    } catch (e, stack) {
      print('❌[SdkManager] IMClient.connect() 失败: $e');
      print('❌[SdkManager] stackTrace: $stack');
      rethrow;
    }

    print('📍[SdkManager] ====== connect() 结束, isConnected=$isConnected ======');
    print('');
  }

  Future<void> disconnect() async {
    print('📍[SdkManager] disconnect() 被调用');
    await client.disconnect();
  }

  Future<void> dispose() async {
    print('📍[SdkManager] dispose() 被调用');
    await client.dispose();
    _isInitialized = false;
  }
}
