import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 消息通知数据模型
class NotificationData {
  final int senderId;
  final String nickname;
  final String? avatarUrl;
  final String content;
  final DateTime time;
  final int targetId; // 会话目标ID（私聊为对方userId，群聊为groupId）
  final bool isGroup;

  const NotificationData({
    required this.senderId,
    required this.nickname,
    this.avatarUrl,
    required this.content,
    required this.time,
    required this.targetId,
    this.isGroup = false,
  });
}

/// 消息通知服务 - 统一管理各平台的消息通知
///
/// 通过 flutter_local_notifications 发送系统原生通知：
/// - Android/iOS：系统通知栏（显示头像图标、昵称、消息内容、时间）
/// - Windows：Toast 通知弹窗（桌面右下角）
/// - macOS：通知中心
/// - Linux：通知中心（如支持）
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// 当前正在聊天会话的 targetId，用于判断是否需要显示通知
  /// 如果收到消息的 targetId 等于此值，则不显示通知（因为用户正在看这个聊天）
  int? _currentChatTargetId;

  set currentChatTargetId(int? value) {
    _currentChatTargetId = value;
  }

  /// 初始化通知服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('🔔[NotificationService] 初始化通知服务...');

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Android: 创建通知渠道（重要程度：高）
    if (!kIsWeb && Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'cao_im_messages',
        '新消息通知',
        description: '来自好友和群组的聊天消息通知',
        importance: Importance.high,
      );
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    _isInitialized = true;
    debugPrint('✅[NotificationService] 通知服务初始化完成');
  }

  /// 显示消息通知（统一入口）
  ///
  /// [data] - 通知数据（发送者信息、消息内容等）
  Future<void> showMessageNotification(NotificationData data) async {
    if (!_isInitialized) {
      debugPrint('⚠️[NotificationService] 通知服务未初始化，跳过通知');
      return;
    }

    // 判断是否需要显示通知：如果用户正在该会话中聊天，则不显示通知
    if (_currentChatTargetId != null && _currentChatTargetId == data.targetId) {
      debugPrint('📍[NotificationService] 用户正在当前会话中聊天(targetId=${data.targetId})，跳过通知');
      return;
    }

    debugPrint('🔔[NotificationService] 显示消息通知: ${data.nickname} - ${data.content}');

    await _showSystemNotification(data);
  }

  /// 发送系统原生通知
  Future<void> _showSystemNotification(NotificationData data) async {
    final androidDetails = AndroidNotificationDetails(
      'cao_im_messages',
      '新消息通知',
      channelDescription: '来自好友和群组的聊天消息通知',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      when: data.time.millisecondsSinceEpoch,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // 使用 senderId 作为通知ID，同一人的新通知会覆盖旧通知
    await _notifications.show(
      data.senderId,
      data.isGroup ? '[${data.nickname}]' : data.nickname,
      _formatContent(data.content),
      details,
      payload: 'chat_${data.targetId}',
    );
  }

  /// 用户点击通知时的回调
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('🔔[NotificationService] 用户点击了通知: payload=${response.payload}');
    // 可在此处处理跳转到对应聊天页面的逻辑
  }

  /// 格式化消息内容（截断过长文本）
  String _formatContent(String content) {
    if (content.length > 50) {
      return '${content.substring(0, 50)}...';
    }
    return content;
  }

  /// 请求通知权限（Android 13+ 需要）
  Future<bool> requestPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      final plugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (plugin != null) {
        final result = await plugin.requestNotificationsPermission();
        debugPrint('🔔[NotificationService] Android 通知权限请求结果: $result');
        return result ?? false;
      }
    }
    if (!kIsWeb && Platform.isIOS) {
      final plugin = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (plugin != null) {
        final result = await plugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return result ?? false;
      }
    }
    return true;
  }

  /// 取消所有通知
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}
