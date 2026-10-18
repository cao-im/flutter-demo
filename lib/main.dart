import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'video_player_setup_stub.dart' if (dart.library.io) 'video_player_setup_io.dart';
import 'providers/auth_provider.dart';
import 'providers/call_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/contact_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/favorite_provider.dart';
import 'providers/layout_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerDesktopVideoPlayer();
  await initializeDateFormatting('zh_CN');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => ContactProvider()),
        ChangeNotifierProvider(create: (_) => LayoutProvider()),
        ChangeNotifierProvider(create: (_) => FavoriteProvider()),
        ChangeNotifierProvider(create: (_) => CallProvider()),
      ],
      child: const CaoApp(),
    ),
  );
}
