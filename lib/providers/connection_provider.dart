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
    _setState(ImConnectionState.connecting);
    try {
      await _sdkManager.initialize(serverUrl: serverUrl);
      _sdkManager.client.addConnectionListener(_ConnectionListener(this));
      _setState(ImConnectionState.disconnected);
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> connect(String token) async {
    _setState(ImConnectionState.connecting);
    try {
      await _sdkManager.connect(token);
    } catch (e) {
      _setError(e.toString());
      _setState(ImConnectionState.disconnected);
    }
  }

  Future<void> disconnect() async {
    await _sdkManager.disconnect();
    _setState(ImConnectionState.disconnected);
  }

  void _setState(ImConnectionState newState) {
    _state = newState;
    _errorMessage = null;
    _safeNotify();
  }

  void _setError(String error) {
    _errorMessage = error;
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
    _provider._setState(ImConnectionState.connected);
  }

  @override
  void onDisconnected() {
    _provider._setState(ImConnectionState.disconnected);
  }

  @override
  void onConnecting() {
    _provider._setState(ImConnectionState.connecting);
  }

  @override
  void onReconnecting() {
    _provider._setState(ImConnectionState.reconnecting);
  }

  @override
  void onReconnectFailed() {
    _provider._setError('重连失败，请检查网络');
  }
}
