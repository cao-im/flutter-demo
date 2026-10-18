import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/layout_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/contact_provider.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';

class DesktopNavigationRail extends StatelessWidget {
  const DesktopNavigationRail({super.key});

  static const double _railWidth = 70.0;
  static const double _itemSize = 48.0;
  static const double _iconSize = 24.0;
  static const double _indicatorWidth = 3.0;
  static const double _avatarSize = 40.0;

  static const List<_NavItem> _navItems = [
    _NavItem(icon: Icons.chat_bubble_outline, label: '消息'),
    _NavItem(icon: Icons.people_outline, label: '通讯录'),
    _NavItem(icon: Icons.star_outline, label: '收藏'),
    _NavItem(icon: Icons.folder_outlined, label: '文件'),
    _NavItem(icon: Icons.settings_outlined, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final layoutProvider = Provider.of<LayoutProvider>(context);
    final selectedIndex = layoutProvider.selectedIndex;
    final authProvider = Provider.of<AuthProvider>(context);
    final friendRequestCount = context.watch<ContactProvider>().unreadFriendRequestCount;

    return Material(
      elevation: 0,
      color: AppTheme.surface(context),
      child: Container(
        width: _railWidth,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: AppTheme.divider(context),
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 8),
            _buildUserAvatar(context, authProvider),
            SizedBox(height: 12),
            Container(
              width: _railWidth - 20,
              height: 1,
              color: AppTheme.divider(context),
            ),
            SizedBox(height: 8),
            ..._navItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isSelected = index == selectedIndex;

              return _buildNavItem(
                context: context,
                icon: item.icon,
                label: item.label,
                isSelected: isSelected,
                badgeCount: index == 1 ? friendRequestCount : 0,
                onTap: () => layoutProvider.selectNavigation(index),
              );
            }),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildUserAvatar(BuildContext context, AuthProvider authProvider) {
    final user = authProvider.user;
    final avatarUrl = user?.avatar;
    final userName = user?.nickname ?? user?.username ?? '用户';

    return Tooltip(
      message: '$userName · 编辑资料',
      preferBelow: false,
      child: InkWell(
        borderRadius: BorderRadius.circular(_avatarSize / 2),
        onTap: () => context.read<LayoutProvider>().selectNavigation(4),
        child: AvatarWidget(
          imageUrl: avatarUrl,
          name: userName,
          size: _avatarSize,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Tooltip(
      message: label,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: _itemSize,
          height: _itemSize,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: _iconSize,
                color: isSelected
                    ? AppTheme.primaryColor
                    : AppTheme.textSecondary(context),
              ),
              if (badgeCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1.4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.label,
  });
}
