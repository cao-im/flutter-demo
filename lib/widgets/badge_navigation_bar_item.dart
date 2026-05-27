import 'package:flutter/material.dart';

class BadgeNavigationBarHelper {
  static BottomNavigationBarItem create({
    required Widget icon,
    Widget? activeIcon,
    required String label,
    int unreadCount = 0,
  }) {
    return BottomNavigationBarItem(
      icon: _buildIconWithBadge(icon, unreadCount),
      activeIcon: _buildIconWithBadge(activeIcon ?? icon, unreadCount),
      label: label,
    );
  }

  static Widget _buildIconWithBadge(Widget icon, int unreadCount) {
    if (unreadCount <= 0) return icon;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -6,
          top: -8,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: BoxConstraints(
              minWidth: 18,
              minHeight: 18,
            ),
            child: Text(
              _formatUnreadCount(unreadCount),
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  static String _formatUnreadCount(int count) {
    if (count > 99) {
      return '99+';
    }
    return count.toString();
  }
}
