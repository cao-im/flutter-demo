import 'dart:convert';

/// 文件消息内容：`{"url":"...","name":"报告.pdf","size":1234}`。
class FileContent {
  static const int maxBytes = 10 * 1024 * 1024;

  static const List<String> allowedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'md',
    'zip',
    'rar',
    'mp3',
    'wav',
    'm4a',
    'aac',
    'amr',
    'ogg',
    'opus',
    'mp4',
    'avi',
    'mov',
  ];

  final String url;
  final String name;
  final int size;

  const FileContent({
    required this.url,
    required this.name,
    required this.size,
  });

  static String encode(String url, String name, int size) {
    return jsonEncode({
      'url': url,
      'name': name,
      'size': size < 0 ? 0 : size,
    });
  }

  static FileContent? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          final url = decoded['url']?.toString().trim() ?? '';
          final name = decoded['name']?.toString().trim() ?? '';
          final size = (decoded['size'] as num?)?.round() ?? 0;
          if (url.isEmpty && name.isEmpty) return null;
          return FileContent(url: url, name: name.isEmpty ? _nameFromUrl(url) : name, size: size);
        }
      } catch (_) {}
    }
    if (text.startsWith('http://') || text.startsWith('https://')) {
      return FileContent(url: text, name: _nameFromUrl(text), size: 0);
    }
    return null;
  }

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static bool isAllowed(String name) {
    return allowedExtensions.contains(extensionOf(name));
  }

  String get sizeLabel {
    if (size <= 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _nameFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final slash = path.replaceAll('\\', '/');
    final name = slash.split('/').last;
    return name.isEmpty ? '文件' : name;
  }
}
