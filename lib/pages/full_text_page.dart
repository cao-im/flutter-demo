import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// 长文本全文页（微信风格：从气泡「全文」进入）
class FullTextPage extends StatelessWidget {
  final String content;
  final String? title;

  const FullTextPage({
    super.key,
    required this.content,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title ?? '全文'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimaryColor,
        elevation: 0.5,
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('复制'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: SelectableText(
            content,
            style: const TextStyle(
              fontSize: 17,
              height: 1.55,
              color: AppTheme.textPrimaryColor,
            ),
          ),
        ),
      ),
    );
  }
}
