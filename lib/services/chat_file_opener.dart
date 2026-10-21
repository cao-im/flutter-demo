import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import '../providers/file_library_provider.dart';
import 'media_store.dart';

/// 聊天气泡和文件库共用：优先打开本机副本，没有就先下载再打开。
class ChatFileOpener {
  static Future<void> open(
    BuildContext context, {
    required String name,
    required String remoteUrl,
    String? localPath,
    String? messageKey,
  }) async {
    try {
      final folder = await MediaStore.folder();
      final already = await MediaStore.exists(localPath);
      if (folder.isNotEmpty && !already && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在保存到本机…')));
      }
      final result = await MediaStore.open(
        knownPath: localPath,
        remoteUrl: remoteUrl,
        name: name,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (result.path.isNotEmpty && messageKey != null && messageKey.isNotEmpty) {
        await context.read<ChatProvider>().rememberMediaPath(messageKey, result.path);
        if (context.mounted) {
          context.read<FileLibraryProvider>().noteLocalPath(messageKey, result.path);
        }
      }
      if (!context.mounted) return;
      if (!result.opened) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开这个文件')));
        return;
      }
      if (result.downloaded && result.folder.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已保存到 ${result.folder}')));
      }
    } catch (error) {
      debugPrint('打开文件失败: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开这个文件')));
    }
  }
}
