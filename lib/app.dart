import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'navigation/app_route.dart';
import 'theme/app_theme.dart';
import 'pages/call_page.dart';
import 'router/app_router.dart';
import 'providers/auth_provider.dart';
import 'providers/connection_provider.dart';

class CaoApp extends StatefulWidget {
  const CaoApp({super.key});

  @override
  State<CaoApp> createState() => _CaoAppState();
}

class _CaoAppState extends State<CaoApp> {
  @override
  void initState() {
    super.initState();
    // SDK 认证永久失效 → 清理登录态并跳转登录页，停止「正在重连」
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ConnectionProvider>().onAuthExpiredCallback = (reason) {
        context.read<AuthProvider>().handleAuthExpired(reason);
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CaoIM',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppRouter.navigatorKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      initialRoute: AppRouter.splash,
      onGenerateRoute: AppRouter.generateRoute,
      builder: (context, child) => KeyboardDismissOnBlank(
        child: CallOverlay(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
