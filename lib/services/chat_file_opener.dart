import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';

import '../navigation/app_route.dart';
import '../models/file_content.dart';
import '../providers/chat_provider.dart';
import '../providers/file_library_provider.dart';
import '../widgets/chat/video_message_content.dart';
import 'media_store.dart';

/// 聊天气泡和文件库共用：优先打开本机副本，没有就先下载再打开。
class ChatFileOpener {
  static const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'};
  static const _videoExt = {'mp4', 'mov', 'avi'};

  static Future<void> open(
    BuildContext context, {
    required String name,
    required String remoteUrl,
    String? localPath,
    String? messageKey,
  }) async {
    final ext = FileContent.extensionOf(name);
    final remote = remoteUrl.trim();
    if (_imageExt.contains(ext)) {
      await _previewImage(context, name: name, remoteUrl: remote, localPath: localPath, messageKey: messageKey);
      return;
    }
    if (_videoExt.contains(ext)) {
      await _previewVideo(context, name: name, remoteUrl: remote, localPath: localPath, messageKey: messageKey);
      return;
    }
    await _openExternal(
      context,
      name: name,
      remoteUrl: remote,
      localPath: localPath,
      messageKey: messageKey,
    );
  }

  static Future<void> _previewImage(
    BuildContext context, {
    required String name,
    required String remoteUrl,
    String? localPath,
    String? messageKey,
  }) async {
    var source = (localPath ?? '').trim();
    if (source.isEmpty || source.startsWith('http://') || source.startsWith('https://') || (kIsWeb || !File(source).existsSync())) {
      final saved = await MediaStore.ensure(knownPath: localPath, remoteUrl: remoteUrl, name: name);
      if (saved.path.isNotEmpty) source = saved.path;
    }
    if (source.isEmpty) source = remoteUrl;
    if (!context.mounted || source.isEmpty) return;
    if (messageKey != null && messageKey.isNotEmpty && !source.startsWith('http')) {
      await context.read<ChatProvider>().rememberMediaPath(messageKey, source);
      if (context.mounted) context.read<FileLibraryProvider>().noteLocalPath(messageKey, source);
    }
    if (!context.mounted) return;
    final display = source;
    await Navigator.of(context).push(
      AppRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Center(
                child: display.startsWith('http')
                    ? PhotoView(imageProvider: NetworkImage(display))
                    : PhotoView(imageProvider: FileImage(File(display))),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _previewVideo(
    BuildContext context, {
    required String name,
    required String remoteUrl,
    String? localPath,
    String? messageKey,
  }) async {
    var source = (localPath ?? '').trim();
    final localReady = source.isNotEmpty && !source.startsWith('http') && !kIsWeb && File(source).existsSync();
    if (!localReady) {
      final saved = await MediaStore.ensure(knownPath: localPath, remoteUrl: remoteUrl, name: name);
      if (saved.path.isNotEmpty) source = saved.path;
    }
    if (source.isEmpty) source = remoteUrl;
    if (!context.mounted || source.isEmpty) return;
    if (messageKey != null && messageKey.isNotEmpty && !source.startsWith('http')) {
      await context.read<ChatProvider>().rememberMediaPath(messageKey, source);
      if (context.mounted) context.read<FileLibraryProvider>().noteLocalPath(messageKey, source);
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(AppRoute(builder: (_) => VideoPlayPage(source: source)));
  }

  static Future<void> _openExternal(
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
