import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cao_im_sdk_flutter/storage/hive/hive_viewer.dart';
import 'app.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/contact_provider.dart';
import 'providers/connection_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 初始化 Hive 数据查看器（用于调试）
  await HiveViewer.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => ContactProvider()),
      ],
      child: const CaoApp(),
    ),
  );
}
