import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// 返回 true 表示已经写入文件。用户取消保存对话框时返回 false。
Future<bool> saveQrPng(Uint8List bytes, String fileName) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存二维码',
      fileName: fileName,
      type: FileType.image,
      bytes: bytes,
    );
    return path != null && path.isNotEmpty;
  }

  final path = await FilePicker.platform.saveFile(
    dialogTitle: '保存二维码',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['png'],
    lockParentWindow: true,
  );
  if (path == null || path.isEmpty) return false;
  final target = path.toLowerCase().endsWith('.png') ? path : '$path.png';
  await File(target).writeAsBytes(bytes, flush: true);
  return true;
}
