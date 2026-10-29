import 'umeng_push_stub.dart'
    if (dart.library.io) 'umeng_push_io.dart' as umeng;

/// 手机端初始化友盟，并把 device token 交给 [PushRegistration]。
/// 桌面和 Web 不初始化。未配置 AppKey 时也不调用原生 SDK。
Future<void> startUmengPush() => umeng.startUmengPush();
