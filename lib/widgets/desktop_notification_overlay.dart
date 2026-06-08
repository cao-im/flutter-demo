import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// 桌面端消息通知弹窗管理器
///
/// 负责在桌面端（Windows/macOS/Linux）右下角显示消息通知弹窗
/// 类似微信、钉钉的消息通知效果：
/// - 从屏幕右下角滑入
/// - 显示发送者头像、昵称、消息内容、时间
/// - 支持多条通知堆叠显示
/// - 自动消失，支持点击跳转
class DesktopNotificationOverlay {
  static DesktopNotificationOverlay? _instance;
  static OverlayEntry? _overlayEntry;
  static final List<_NotificationItem> _notifications = [];
  static const double _notificationWidth = 340.0;
  static const double _notificationHeight = 80.0;
  static const int _maxVisibleCount = 4; // 最多同时显示4条通知
  static const Duration _autoDismissDuration = Duration(seconds: 5);
  static const Duration _slideOutDuration = Duration(milliseconds: 200);

  /// 当前 BuildContext（用于显示 Overlay）
  static BuildContext? _context;

  /// 点击通知的回调
  static void Function(NotificationData data)? onNotificationTap;

  /// 初始化通知管理器（需要在有 MaterialApp 的 context 下调用）
  static void init(BuildContext context) {
    _context = context;
    _instance ??= DesktopNotificationOverlay._();
  }

  /// 显示一条新消息通知
  static void showNotification(NotificationData data) {
    if (_context == null) {
      debugPrint('⚠️[DesktopNotification] _context 为空，无法显示通知');
      return;
    }

    // 如果已存在相同 targetId 的通知，先移除旧的
    _notifications.removeWhere((item) => item.data.targetId == data.targetId);

    // 添加新通知到列表头部（最新的在最上面）
    late final _NotificationItem item;
    item = _NotificationItem(
      data: data,
      key: UniqueKey(),
      onDismiss: () => _removeNotification(item),
      onTap: () {
        onNotificationTap?.call(data);
        _removeNotification(item);
      },
    );

    _notifications.insert(0, item);

    // 限制最大数量
    while (_notifications.length > _maxVisibleCount) {
      final removed = _notifications.removeLast();
      removed.controller.reverse(); // 动画移除最旧的通知
    }

    // 更新或创建 Overlay
    _updateOverlay();
  }

  /// 移除指定通知
  static void _removeNotification(_NotificationItem item) {
    item.controller.reverse().then((_) {
      _notifications.remove(item);
      if (_notifications.isEmpty) {
        _removeOverlay();
      } else {
        _rebuildOverlay();
      }
    });
  }

  /// 清空所有通知
  static void dismissAll() {
    for (final item in _notifications) {
      item.controller.reverse();
    }
    _notifications.clear();
    _removeOverlay();
  }

  /// 更新 Overlay 内容
  static void _updateOverlay() {
    if (_overlayEntry == null) {
      _createOverlay();
    } else {
      _rebuildOverlay();
    }
  }

  /// 创建 Overlay
  static void _createOverlay() {
    if (_context == null || _notifications.isEmpty) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => _DesktopNotificationStack(
        notifications: List.unmodifiable(_notifications),
        notificationWidth: _notificationWidth,
        notificationHeight: _notificationHeight,
      ),
    );

    Overlay.of(_context!).insert(_overlayEntry!);
  }

  /// 重建 Overlay（不销毁重建，只刷新内容）
  static void _rebuildOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  /// 移除 Overlay
  static void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  DesktopNotificationOverlay._();

  /// 销毁管理器
  static void dispose() {
    dismissAll();
    _instance = null;
    _context = null;
  }
}

/// 通知条目数据
class _NotificationItem {
  final NotificationData data;
  final Key key;
  late AnimationController controller;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  _NotificationItem({
    required this.data,
    required this.key,
    required this.onDismiss,
    required this.onTap,
  });
}

/// 桌面端通知栈组件（渲染所有通知）
class _DesktopNotificationStack extends StatefulWidget {
  final List<_NotificationItem> notifications;
  final double notificationWidth;
  final double notificationHeight;

  // 静态 TickerProvider（供子项使用）
  static TickerProvider? _tickerProvider;

  const _DesktopNotificationStack({
    super.key,
    required this.notifications,
    required this.notificationWidth,
    required this.notificationHeight,
  });

  @override
  State<_DesktopNotificationStack> createState() => _DesktopNotificationStackState();
}

class _DesktopNotificationStackState extends State<_DesktopNotificationStack>
    with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    _DesktopNotificationStack._tickerProvider = this;

    // 初始化所有通知的 AnimationController
    for (final item in widget.notifications) {
      item.controller = AnimationController(
        vsync: this,
        duration: DesktopNotificationOverlay._slideOutDuration,
      );
      item.controller.forward(); // 立即播放滑入动画
    }

    // 启动自动消失定时器
    for (final item in widget.notifications) {
      Future.delayed(DesktopNotificationOverlay._autoDismissDuration, () {
        if (mounted && widget.notifications.contains(item)) {
          item.onDismiss();
        }
      });
    }
  }

  @override
  void dispose() {
    // 释放所有 AnimationController
    for (final item in widget.notifications) {
      item.controller.dispose();
    }
    _DesktopNotificationStack._tickerProvider = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: widget.notifications.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return Padding(
            padding: EdgeInsets.only(top: index > 0 ? 8 : 0),
            child: _DesktopNotificationCard(
              key: item.key,
              data: item.data,
              width: widget.notificationWidth,
              height: widget.notificationHeight,
              animation: item.controller,
              onTap: item.onTap,
              onClose: item.onDismiss,
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 单个桌面通知卡片（类似微信/钉钉风格）
class _DesktopNotificationCard extends StatelessWidget {
  final NotificationData data;
  final double width;
  final double height;
  final Animation<double> animation;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _DesktopNotificationCard({
    super.key,
    required this.data,
    required this.width,
    required this.height,
    required this.animation,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.2, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // 主内容区
              Row(
                children: [
                  // 左侧头像区域
                  Container(
                    width: height,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor.withValues(alpha: 0.08),
                          AppTheme.primaryColor.withValues(alpha: 0.03),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: _buildAvatar(),
                    ),
                  ),

                  // 右侧信息区域
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 第一行：昵称 + 时间
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  data.isGroup
                                      ? '[${data.nickname}]'
                                      : data.nickname,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimaryColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                _formatTime(data.time),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),

                          // 第二行：消息内容预览
                          Text(
                            data.content,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondaryColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // 右上角关闭按钮
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.04),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final avatarSize = 44.0;

    if (data.avatarUrl != null && data.avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: avatarSize / 2,
        backgroundImage: CachedNetworkImageProvider(data.avatarUrl!),
        backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
      );
    }

    return CircleAvatar(
      radius: avatarSize / 2,
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
      child: Text(
        data.nickname.isNotEmpty ? data.nickname[0] : '?',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final isToday = now.year == time.year &&
        now.month == time.month &&
        now.day == time.day;

    if (isToday) {
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else {
      return '${time.month}/${time.day}';
    }
  }
}
