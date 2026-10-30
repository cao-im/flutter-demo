import 'package:flutter/foundation.dart';

/// 服务地址。可用编译参数覆盖，例如：
/// flutter run --dart-define=APP_SERVER_URL=http://192.168.0.10:8081/api --dart-define=IM_SERVER_URL=http://192.168.0.10:8080/api --dart-define=IM_WS_URL=ws://192.168.0.10:8080/api/ws
class ServerConfig {
  static const String _appOverride = String.fromEnvironment('APP_SERVER_URL');
  static const String _imOverride = String.fromEnvironment('IM_SERVER_URL');
  static const String _wsOverride = String.fromEnvironment('IM_WS_URL');

  static String get appServerUrl =>
      _appOverride.isNotEmpty ? _appOverride : _url('http', 8081, '/api');

  static String get imServerUrl =>
      _imOverride.isNotEmpty ? _imOverride : _url('http', 8080, '/api');

  static String get imWebSocketUrl =>
      _wsOverride.isNotEmpty ? _wsOverride : _url('ws', 8080, '/api/ws');

  /// 资料里的头像常被存成 127.0.0.1。手机上这是设备自己，换成当前应用服务地址才能打开。
  static String reachableFileUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return raw;
    final host = uri.host.toLowerCase();
    if (host != '127.0.0.1' && host != 'localhost' && host != '::1') return raw;
    final app = Uri.tryParse(appServerUrl);
    if (app == null || app.host.isEmpty) return raw;
    return uri.replace(
      scheme: app.scheme.isEmpty ? uri.scheme : app.scheme,
      host: app.host,
      port: app.hasPort ? app.port : uri.port,
    ).toString();
  }

  /// Android 模拟器里的 localhost 是模拟器自己。10.0.2.2 才指向运行模拟器的这台电脑。
  static String _url(String scheme, int port, String path) {
    final host = '192.168.0.138';
    return '$scheme://$host:$port$path';
  }
}
