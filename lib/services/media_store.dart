import 'package:flutter/widgets.dart';

import 'media_store_result.dart';
import 'media_store_web.dart' if (dart.library.io) 'media_store_io.dart' as store;

export 'media_store_result.dart';

/// 聊天附件在本机的副本。桌面和手机放在文档目录的 CAO-IM/files，网页端仍用浏览器打开。
class MediaStore {
  static Future<String> folder() => store.folder();

  static Future<bool> exists(String? path) => store.exists(path);

  static Future<String> keepFile(String sourcePath, String name) => store.keepFile(sourcePath, name);

  static Future<String> keepBytes(List<int> bytes, String name) => store.keepBytes(bytes, name);

  static Future<OpenResult> ensure({
    String? knownPath,
    required String remoteUrl,
    required String name,
  }) {
    return store.ensure(knownPath: knownPath, remoteUrl: remoteUrl, name: name);
  }

  static Future<OpenResult> open({
    String? knownPath,
    required String remoteUrl,
    required String name,
  }) {
    return store.open(knownPath: knownPath, remoteUrl: remoteUrl, name: name);
  }

  static Future<bool> reveal(String path) => store.reveal(path);

  static Widget image(String source, {required Widget error}) => store.image(source, error: error);
}
