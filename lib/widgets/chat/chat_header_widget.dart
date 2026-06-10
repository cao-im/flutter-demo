import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 标题栏样式
enum ChatHeaderStyle {
  /// 移动端 AppBar 形态（带背景色、高度56）
  appBar,
  /// 桌面端 Panel 形态（白色背景、带底部分割线、高度自适应）
  panel,
}

/// 聊天页面顶部标题栏组件 — 支持移动端AppBar和桌面端Panel两种形态
class ChatHeaderWidget extends StatelessWidget implements PreferredSizeWidget {
  /// 标题文字
  final String title;

  /// 副标题文字（如"在线"、"群聊"、"公众号"）
  final String? subtitle;

  /// 显示样式
  final ChatHeaderStyle style;

  /// 是否显示语音通话按钮
  final bool showVoiceCall;

  /// 是否显示视频通话按钮
  final bool showVideoCall;

  /// 更多按钮回调
  final VoidCallback? onMoreTap;

  /// 语音通话回调
  final VoidCallback? onVoiceCallTap;

  /// 视频通话回调
  final VoidCallback? onVideoCallTap;

  const ChatHeaderWidget({
    super.key,
    required this.title,
    this.subtitle,
    this.style = ChatHeaderStyle.appBar,
    this.showVoiceCall = false,
    this.showVideoCall = false,
    this.onMoreTap,
    this.onVoiceCallTap,
    this.onVideoCallTap,
  });

  @override
  Size get preferredSize {
    switch (style) {
      case ChatHeaderStyle.appBar:
        return const Size.fromHeight(56); // 标准 AppBar 高度
      case ChatHeaderStyle.panel:
        return const Size.fromHeight(52); // 桌面端 header 高度
    }
  }

  @override
  Widget build(BuildContext context) {
    if (style == ChatHeaderStyle.appBar) {
      return AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.more_vert), onPressed: onMoreTap ?? () {}),
        ],
      );
    }

    // 桌面端 Panel Header
    final hp = style == ChatHeaderStyle.panel ? 20.0 : 16.0;
    final vp = style == ChatHeaderStyle.panel ? 14.0 : 12.0;
    final iconSize = style == ChatHeaderStyle.panel ? 22.0 : 20.0;
    final btnSize = style == ChatHeaderStyle.panel ? 36.0 : 32.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hp, vertical: vp),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: style == ChatHeaderStyle.panel ? 17.0 : 16.0,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimaryColor,
              ),
            ),
          ),

          // 语音通话按钮（仅 panel 模式且 showVoiceCall 时显示）
          if (showVoiceCall && style == ChatHeaderStyle.panel) ...[
            _buildActionButton(Icons.phone_outlined, '语音通话', btnSize, iconSize, onVoiceCallTap),
            const SizedBox(width: 4),
          ],

          // 视频通话按钮（仅 panel 模式且 showVideoCall 时显示）
          if (showVideoCall && style == ChatHeaderStyle.panel) ...[
            _buildActionButton(Icons.videocam_outlined, '视频通话', btnSize, iconSize, onVideoCallTap),
            const SizedBox(width: 4),
          ],

          // 更多按钮
          _buildActionButton(Icons.more_vert, '更多', btnSize, iconSize, onMoreTap),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String tooltip, double size, double iconSize, VoidCallback? onTap) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        icon: Icon(icon, size: iconSize),
        tooltip: tooltip,
        onPressed: onTap ?? () {},
        style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    );
  }
}
