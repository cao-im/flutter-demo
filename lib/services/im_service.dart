@Deprecated('请使用 IMSdkManager 和 IMClient 替代')
class IMService {
  static const String wsUrl = 'ws://localhost:8080/api/ws';

  bool get isConnected => false;

  IMService({
    required dynamic onMessageReceived,
    dynamic onConnected,
    dynamic onDisconnected,
    dynamic onError,
  });

  Future<void> connect(String token) async {
    throw UnimplementedError('IMService 已废弃，请使用 IMSdkManager');
  }

  void sendMessage(Map<String, dynamic> message) {
    throw UnimplementedError('IMService 已废弃，请使用 IMSdkManager.client.sendMessage()');
  }

  void disconnect() {
    throw UnimplementedError('IMService 已废弃，请使用 IMSdkManager.disconnect()');
  }

  void dispose() {
    throw UnimplementedError('IMService 已废弃，请使用 IMSdkManager.dispose()');
  }
}
