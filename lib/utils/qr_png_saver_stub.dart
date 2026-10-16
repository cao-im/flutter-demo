import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

/// 浏览器直接下载 PNG。
Future<bool> saveQrPng(Uint8List bytes, String fileName) async {
  final blob = Blob([bytes.toJS].toJS, BlobPropertyBag(type: 'image/png'));
  final url = URL.createObjectURL(blob);
  HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..click();
  URL.revokeObjectURL(url);
  return true;
}
