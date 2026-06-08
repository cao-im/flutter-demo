import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

/// 消息通知数据模型
class NotificationData {
  final int senderId;
  final String nickname;
  final String? avatarUrl;
  final String content;
  final DateTime time;
  final int targetId;
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

/// 消息提示服务 - 收到新消息时播放提示音
///
/// 核心逻辑：收到新消息 → 不在当前聊天界面 → 播放 new_msg.wav
///
/// 各平台播放方式（均使用 new_msg.wav）：
/// - Android：通过系统通知渠道的自定义提示音播放
/// - iOS：通过系统通知的默认提示音播放
/// - Windows：通过 PowerShell 的 SoundPlayer 播放 wav 文件
/// - macOS：通过 afplay 命令播放 wav 文件
/// - Linux：通过 aplay/aplay 命令播放 wav 文件
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// wav 文件在 assets 中的路径
  static const String _soundAssetPath = 'assets/sounds/new_msg.wav';

  /// 当前正在聊天会话的 targetId
  int? _currentChatTargetId;

  set currentChatTargetId(int? value) {
    _currentChatTargetId = value;
  }

  /// 初始化
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('🔔[NotificationService] 初始化...');

    // Android/iOS：初始化通知插件（用于播放提示音）
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _notifications.initialize(
      InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Android：配置自定义提示音的通知渠道
    if (!kIsWeb && Platform.isAndroid) {
      await _setupAndroidChannel();
    }

    // 预先将 wav 文件从 assets 复制到本地文件系统（Windows/macOS/Linux 需要文件路径）
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      await _extractSoundFile();
    }

    _isInitialized = true;
    debugPrint('✅[NotificationService] 初始化完成');
  }

  /// Android：创建带自定义提示音的通知渠道（删旧建新确保生效）
  Future<void> _setupAndroidChannel() async {
    final plugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (plugin == null) return;

    try {
      // 先删旧渠道（Android 渠道创建后声音不可修改，必须重建）
      await plugin.deleteNotificationChannel('cao_im_msg');

      const channel = AndroidNotificationChannel(
        'cao_im_msg',
        '新消息',
        description: '新消息提示',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('new_msg'),
      );
      await plugin.createNotificationChannel(channel);
      debugPrint('✅[NotificationService] Android 提示音渠道已设置');
    } catch (e) {
      debugPrint('⚠️[NotificationService] Android 提示音设置失败: $e');
    }
  }

  /// 将 assets 中的 wav 提取到本地临时目录（桌面端需要文件路径来播放）
  Future<void> _extractSoundFile() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/new_msg.wav');
      if (!await file.exists()) {
        final byteData = await rootBundle.load(_soundAssetPath);
        await file.writeAsBytes(byteData.buffer.asUint8List());
        debugPrint('✅[NotificationService] wav 已提取到: ${file.path}');
      }
    } catch (e) {
      debugPrint('⚠️[NotificationService] wav 提取失败: $e');
    }
  }

  /// 显示消息通知（统一入口）→ 实际就是播放提示音
  Future<void> showMessageNotification(NotificationData data) async {
    // 1. 未初始化 → 不播放
    if (!_isInitialized) {
      debugPrint('🔕[通知] ❌ 不播放：服务未初始化');
      return;
    }

    // 2. 正在当前会话聊天 → 不播放
    if (_currentChatTargetId != null && _currentChatTargetId == data.targetId) {
      debugPrint('🔕[通知] ⏭️ 不播放：正在与 ${data.nickname} 聊天 (targetId=${data.targetId}, currentChatTargetId=$_currentChatTargetId)');
      return;
    }

    // 3. 决定播放
    debugPrint('🔔[通知] ✅ 播放提示音：来自「${data.nickname}」的消息 (targetId=${data.targetId})');

    await _playSound();
  }

  /// 播放提示音（按平台分发）
  Future<void> _playSound() async {
    if (kIsWeb) {
      debugPrint('🔕[通知] ⏭️ 不播放：当前为 Web 平台');
      return;
    }

    final platform = _platformLabel();

    if (Platform.isAndroid || Platform.isIOS) {
      debugPrint('🔊[通知] 📱 使用 $platform 通知渠道播放提示音...');
      await _playViaNotification();
    } else if (Platform.isWindows) {
      debugPrint('🔊[通知] 💻 使用 PowerShell SoundPlayer 播放 wav...');
      await _playViaPowerShell();
    } else if (Platform.isMacOS) {
      debugPrint('🔊[通知] 🍎 使用 afplay 播放 wav...');
      await _playViaAfplay();
    } else if (Platform.isLinux) {
      debugPrint('🔊[通知] 🐧 使用 aplay 播放 wav...');
      await _playViaAplay();
    } else {
      debugPrint('🔕[通知] ⏭️ 不播放：未知平台');
    }
  }

  /// 获取当前平台标签
  String _platformLabel() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// 移动端：通过通知播放提示音
  Future<void> _playViaNotification() async {
    try {
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        '',
        '',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'cao_im_msg', '新消息',
            channelDescription: '新消息提示',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: true,
          ),
        ),
      );
      debugPrint('🔊[通知] ✅ 通知已发送，提示音应已播放');
    } catch (e) {
      debugPrint('🔕[通知] ❌ 通知提示音播放失败: $e');
    }
  }

  /// Windows：PowerShell 播放 wav
  Future<void> _playViaPowerShell() async {
    try {
      final dir = await getTemporaryDirectory();
      final wavPath = '${dir.path}\\new_msg.wav';
      final file = File(wavPath);

      if (!await file.exists()) {
        debugPrint('🔕[通知] ❌ Windows 播放失败：wav 文件不存在 ($wavPath)');
        return;
      }

      debugPrint('🔊[通知] 📂 wav 文件路径: $wavPath');

      final result = await Process.run(
        'powershell',
        ['-Command', '(New-Object System.Media.SoundPlayer "$wavPath").PlaySync()'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        debugPrint('🔊[通知] ✅ Windows 提示音播放完成');
      } else {
        debugPrint('🔕[通知] ❌ Windows 播放异常 (exitCode=${result.exitCode}): ${result.stderr}');
      }
    } catch (e) {
      debugPrint('🔕[通知] ❌ Windows 播放异常: $e');
    }
  }

  /// macOS：afplay 播放 wav
  Future<void> _playViaAfplay() async {
    try {
      final dir = await getTemporaryDirectory();
      final wavPath = '$dir/new_msg.wav';
      final file = File(wavPath);

      if (!await file.exists()) {
        debugPrint('🔕[通知] ❌ macOS 播放失败：wav 文件不存在 ($wavPath)');
        return;
      }

      debugPrint('🔊[通知] 📂 wav 文件路径: $wavPath');

      final result = await Process.run('afplay', [wavPath]);

      if (result.exitCode == 0) {
        debugPrint('🔊[通知] ✅ macOS 提示音播放完成');
      } else {
        debugPrint('🔕[通知] ❌ macOS 播放异常 (exitCode=${result.exitCode}): ${result.stderr}');
      }
    } catch (e) {
      debugPrint('🔕[通知] ❌ macOS 播放异常: $e');
    }
  }

  /// Linux：aplay 播放 wav
  Future<void> _playViaAplay() async {
    try {
      final dir = await getTemporaryDirectory();
      final wavPath = '$dir/new_msg.wav';
      final file = File(wavPath);

      if (!await file.exists()) {
        debugPrint('🔕[通知] ❌ Linux 播放失败：wav 文件不存在 ($wavPath)');
        return;
      }

      debugPrint('🔊[通知] 📂 wav 文件路径: $wavPath');

      final result = await Process.run('aplay', ['-q', wavPath]);

      if (result.exitCode == 0) {
        debugPrint('🔊[通知] ✅ Linux 提示音播放完成');
      } else {
        debugPrint('🔕[通知] ❌ Linux 播放异常 (exitCode=${result.exitCode}): ${result.stderr}');
      }
    } catch (e) {
      debugPrint('🔕[通知] ❌ Linux 播放异常: $e');
    }
  }

  void dispose() {
    _currentChatTargetId = null;
  }

  /// 请求通知权限（Android 13+ 需要）
  Future<bool> requestPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      final plugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (plugin != null) {
        return await plugin.requestNotificationsPermission() ?? false;
      }
    }
    if (!kIsWeb && Platform.isIOS) {
      final plugin = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (plugin != null) {
        return await plugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ?? false;
      }
    }
    return true;
  }
}
