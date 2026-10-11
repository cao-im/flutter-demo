/// 服务地址。可用编译参数覆盖，例如：
/// flutter run --dart-define=APP_SERVER_URL=http://192.168.0.10:8081/api --dart-define=IM_SERVER_URL=http://192.168.0.10:8080/api --dart-define=IM_WS_URL=ws://192.168.0.10:8080/api/ws
class ServerConfig {
  static const String appServerUrl = String.fromEnvironment(
    'APP_SERVER_URL',
    defaultValue: 'http://localhost:8081/api',
  );

  static const String imServerUrl = String.fromEnvironment(
    'IM_SERVER_URL',
    defaultValue: 'http://localhost:8080/api',
  );

  static const String imWebSocketUrl = String.fromEnvironment(
    'IM_WS_URL',
    defaultValue: 'ws://localhost:8080/api/ws',
  );
}
