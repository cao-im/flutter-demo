import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart';
import '../sdk/im_sdk_manager.dart';

enum ImConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class ConnectionProvider with ChangeNotifier {
  final IMSdkManager _sdkManager = IMSdkManager();
  ImConnectionState _state = ImConnectionState.disconnected;
  String? _errorMessage;

  ImConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _state == ImConnectionState.connected;
  bool get isInitialized => _sdkManager.isInitialized;

  IMSdkManager get sdkManager => _sdkManager;

  Future<void> initialize(String serverUrl) async {
    debugPrint('📍[ConnProvider] ====== initialize() 开始 ======');
    debugPrint('📍[ConnProvider] serverUrl: $serverUrl');
    debugPrint('📍[ConnProvider] 当前状态: $_state');

    _setState(ImConnectionState.connecting);

    try {
      debugPrint('📍[ConnProvider] 调用 IMSdkManager.initialize()...');
      await _sdkManager.initialize(serverUrl: serverUrl);
      debugPrint('📍[ConnProvider] IMSdkManager.initialize() 成功');

      debugPrint('📍[ConnProvider] 添加 ConnectionListener...');
      _sdkManager.client.addConnectionListener(_ConnectionListener(this));
      debugPrint('📍[ConnProvider] ConnectionListener 已添加');

      debugPrint('📍[ConnProvider] 初始化完成，状态设为 disconnected (等待connect)');
      _setState(ImConnectionState.disconnected);
    } catch (e, stack) {
      debugPrint('❌[ConnProvider] initialize 失败: $e');
      debugPrint('❌[ConnProvider] stackTrace: $stack');
      _setError(e.toString());
    }

    debugPrint('📍[ConnProvider] ====== initialize() 结束, 最终状态: $_state ======');
  }

  Future<void> connect(String token, {int? userId, String? refreshToken}) async {
    debugPrint('');
    debugPrint('📍[ConnProvider] ====== connect() 开始 ======');
    debugPrint('📍[ConnProvider] token长度: ${token?.length ?? 0}');
    debugPrint('📍[ConnProvider] refreshToken: ${refreshToken != null ? "有" : "无"}');
    debugPrint('📍[ConnProvider] userId: $userId');
    debugPrint('📍[ConnProvider] isInitialized: ${_sdkManager.isInitialized}');
    debugPrint('📍[ConnProvider] 当前状态: $_state');

    if (!_sdkManager.isInitialized) {
      debugPrint('⚠️[ConnProvider] SDK 未初始化，跳过连接');
      return;
    }

    _setState(ImConnectionState.connecting);

    try {
      debugPrint('📍[ConnProvider] 调用 IMSdkManager.connect(token, userId: $userId, refreshToken: ${refreshToken != null ? "有" : "无"})...');
      await _sdkManager.connect(token, userId: userId, refreshToken: refreshToken);
      debugPrint('✅[ConnProvider] IMSdkManager.connect() 返回成功');
    } catch (e, stack) {
      debugPrint('❌[ConnProvider] connect 失败: $e');
      debugPrint('❌[ConnProvider] stackTrace: $stack');
      _setError(e.toString());
      _setState(ImConnectionState.disconnected);
    }

    debugPrint('📍[ConnProvider] ====== connect() 结束, 最终状态: $_state ======');
    debugPrint('');
  }

  Future<void> disconnect() async {
    debugPrint('📍[ConnProvider] disconnect() 被调用');
    await _sdkManager.disconnect();
    _setState(ImConnectionState.disconnected);
  }

  void _setState(ImConnectionState newState) {
    final oldState = _state;
    _state = newState;
    _errorMessage = null;
    debugPrint('🔄[ConnProvider] 状态变化: $oldState → $newState');
    _safeNotify();
  }

  void _setError(String error) {
    _errorMessage = error;
    debugPrint('❌[ConnProvider] 设置错误: $error');
    _safeNotify();
  }

  void _safeNotify() {
    scheduleMicrotask(() {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }
}

class _ConnectionListener implements ConnectionListener {
  final ConnectionProvider _provider;
  _ConnectionListener(this._provider);

  @override
  void onConnected() {
    debugPrint('🔗[ConnListener] 收到 onConnected 回调');
    _provider._setState(ImConnectionState.connected);
  }

  @override
  void onDisconnected() {
    debugPrint('🔌[ConnListener] 收到 onDisconnected 回调');
    _provider._setState(ImConnectionState.disconnected);
  }

  @override
  void onConnecting() {
    debugPrint('⏳[ConnListener] 收到 onConnecting 回调');
    _provider._setState(ImConnectionState.connecting);
  }

  @override
  void onReconnecting() {
    debugPrint('🔄[ConnListener] 收到 onReconnecting 回调');
    _provider._setState(ImConnectionState.reconnecting);
  }

  @override
  void onReconnectFailed() {
    debugPrint('❌[ConnListener] 收到 onReconnectFailed 回调');
    _provider._setError('重连失败，请检查网络');
  }

  @override
  void onReconnectingStateChanged(bool isReconnecting) {
    debugPrint('📊[ConnListener] 重连状态变更: $isReconnecting');
    if (isReconnecting) {
      _provider._setState(ImConnectionState.reconnecting);
    }
  }
}
