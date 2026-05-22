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
    if (_isInitialized) return;

    await client.init(serverUrl: serverUrl);
    _isInitialized = true;
  }

  Future<void> connect(String token) async {
    if (!_isInitialized) {
      throw Exception('SDK 未初始化，请先调用 initialize');
    }
    await client.connect(token);
  }

  Future<void> disconnect() async {
    await client.disconnect();
  }

  Future<void> dispose() async {
    await client.dispose();
    _isInitialized = false;
  }
}
