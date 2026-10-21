import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'media_store_result.dart';

Future<String> folder() async => '';

Future<bool> exists(String? path) async => false;

Future<String> keepFile(String sourcePath, String name) async => '';

Future<String> keepBytes(List<int> bytes, String name) async => '';

Future<OpenResult> ensure({
  String? knownPath,
  required String remoteUrl,
  required String name,
}) async {
  return const OpenResult();
}

Future<OpenResult> open({
  String? knownPath,
  required String remoteUrl,
  required String name,
}) async {
  final url = remoteUrl.trim();
  if (url.startsWith('http://') || url.startsWith('https://')) {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return OpenResult(opened: opened);
  }
  return const OpenResult();
}

Future<bool> reveal(String path) async => false;

Widget image(String source, {required Widget error}) {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return Image.network(source, fit: BoxFit.contain, errorBuilder: (_, __, ___) => error);
  }
  return error;
}
