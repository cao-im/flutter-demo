import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'media_store_result.dart';

Future<Directory> _directory() async {
  final documents = await getApplicationDocumentsDirectory();
  final folder = Directory('${documents.path}${Platform.pathSeparator}CAO-IM${Platform.pathSeparator}files');
  if (!await folder.exists()) {
    await folder.create(recursive: true);
  }
  return folder;
}

Future<String> folder() async => (await _directory()).path;

Future<bool> exists(String? path) async {
  final value = (path ?? '').trim();
  if (value.isEmpty || value.startsWith('http://') || value.startsWith('https://')) return false;
  return File(value).exists();
}

String _safeName(String name) {
  final base = name.trim().replaceAll('\\', '/').split('/').last;
  final cleaned = base.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
  if (cleaned.isEmpty) return 'file';
  return cleaned.length > 80 ? cleaned.substring(cleaned.length - 80) : cleaned;
}

String _hash(String input) {
  var value = 0;
  for (final unit in input.codeUnits) {
    value = (value * 31 + unit) & 0x7fffffff;
  }
  return value.toRadixString(16);
}

Future<File> _cachedFile(String remoteUrl, String name) async {
  final dir = await _directory();
  final remote = remoteUrl.trim();
  final prefix = remote.startsWith('http://') || remote.startsWith('https://')
      ? _hash(remote)
      : DateTime.now().millisecondsSinceEpoch.toString();
  return File('${dir.path}${Platform.pathSeparator}${prefix}_${_safeName(name)}');
}

Future<String> keepFile(String sourcePath, String name) async {
  final source = File(sourcePath);
  if (!await source.exists()) return '';
  final dir = await _directory();
  final parent = source.parent.path;
  if (parent == dir.path) return source.path;
  final dest = File(
    '${dir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_${_safeName(name)}',
  );
  await source.copy(dest.path);
  return dest.path;
}

Future<String> keepBytes(List<int> bytes, String name) async {
  if (bytes.isEmpty) return '';
  final dir = await _directory();
  final dest = File(
    '${dir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_${_safeName(name)}',
  );
  await dest.writeAsBytes(bytes, flush: true);
  return dest.path;
}

Future<OpenResult> ensure({
  String? knownPath,
  required String remoteUrl,
  required String name,
}) async {
  final dir = await folder();
  final known = (knownPath ?? '').trim();
  if (await exists(known)) {
    return OpenResult(path: known, folder: dir);
  }
  final remote = remoteUrl.trim();
  if (remote.isNotEmpty && !remote.startsWith('http://') && !remote.startsWith('https://') && await exists(remote)) {
    return OpenResult(path: remote, folder: dir);
  }
  if (!remote.startsWith('http://') && !remote.startsWith('https://')) {
    return OpenResult(folder: dir);
  }
  final target = await _cachedFile(remote, name);
  if (await target.exists() && await target.length() > 0) {
    return OpenResult(path: target.path, folder: dir);
  }
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 2),
    responseType: ResponseType.bytes,
  ));
  final response = await dio.get<List<int>>(remote);
  final data = response.data;
  if (data == null || data.isEmpty) {
    return OpenResult(folder: dir);
  }
  await target.writeAsBytes(data, flush: true);
  return OpenResult(path: target.path, folder: dir, downloaded: true);
}

Future<bool> _launch(String path) async {
  if (Platform.isWindows) {
    await Process.run('cmd.exe', ['/c', 'start', '', path]);
    return true;
  }
  if (Platform.isMacOS) {
    final result = await Process.run('open', [path]);
    return result.exitCode == 0;
  }
  final result = await Process.run('xdg-open', [path]);
  return result.exitCode == 0;
}

Future<OpenResult> open({
  String? knownPath,
  required String remoteUrl,
  required String name,
}) async {
  final saved = await ensure(knownPath: knownPath, remoteUrl: remoteUrl, name: name);
  if (saved.path.isEmpty) {
    final remote = remoteUrl.trim();
    if (remote.startsWith('http://') || remote.startsWith('https://')) {
      return OpenResult(folder: saved.folder, opened: false);
    }
    return saved;
  }
  final opened = await _launch(saved.path);
  return OpenResult(
    path: saved.path,
    opened: opened,
    folder: saved.folder,
    downloaded: saved.downloaded,
  );
}

Future<bool> reveal(String path) async {
  final target = path.trim().isEmpty ? await folder() : path.trim();
  if (target.isEmpty) return false;
  if (Platform.isWindows) {
    if (await File(target).exists()) {
      await Process.run('explorer.exe', ['/select,$target']);
    } else {
      await Process.run('explorer.exe', [Directory(target).existsSync() ? target : await folder()]);
    }
    return true;
  }
  if (Platform.isMacOS) {
    final args = await File(target).exists() ? ['-R', target] : [await folder()];
    final result = await Process.run('open', args);
    return result.exitCode == 0;
  }
  final directory = await File(target).exists() ? File(target).parent.path : await folder();
  final result = await Process.run('xdg-open', [directory]);
  return result.exitCode == 0;
}

Widget image(String source, {required Widget error}) {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return Image.network(source, fit: BoxFit.contain, errorBuilder: (_, __, ___) => error);
  }
  return Image.file(File(source), fit: BoxFit.contain, errorBuilder: (_, __, ___) => error);
}
