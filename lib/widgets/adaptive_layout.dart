import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AdaptiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget desktop;

  const AdaptiveLayout({
    super.key,
    required this.mobile,
    required this.desktop,
  });

  static bool get isDesktopPlatform {
    if (kIsWeb) return true;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) {
      debugPrint('🖥️[AdaptiveLayout] 检测到桌面端平台，使用桌面布局');
      return desktop;
    } else {
      debugPrint('📱[AdaptiveLayout] 检测到移动端平台，使用移动布局');
      return mobile;
    }
  }
}
