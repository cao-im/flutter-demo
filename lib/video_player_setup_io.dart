import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player_win/video_player_win.dart';

void registerDesktopVideoPlayer() {
  if (!kIsWeb && Platform.isWindows) {
    WindowsVideoPlayer.registerWith();
  }
}
