import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'router/app_router.dart';

class CaoApp extends StatelessWidget {
  const CaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CaoIM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      initialRoute: AppRouter.splash,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
