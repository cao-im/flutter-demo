import 'dart:convert';

/// 视频消息内容：`{"url","name","size","duration","cover"}`。
class VideoContent {
  static const int maxBytes = 50 * 1024 * 1024;
  static const int maxSeconds = 5 * 60;

  static const List<String> allowedExtensions = ['mp4', 'mov', 'avi'];

  final String url;
  final String name;
  final int size;
  final int duration;
  final String cover;

  const VideoContent({
    required this.url,
    required this.name,
    required this.size,
    required this.duration,
    this.cover = '',
  });

  static String encode({
    required String url,
    required String name,
    required int size,
    required int duration,
    String cover = '',
  }) {
    return jsonEncode({
      'url': url,
      'name': name,
      'size': size < 0 ? 0 : size,
      'duration': duration < 0 ? 0 : duration,
      'cover': cover,
    });
  }

  static VideoContent? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          final url = decoded['url']?.toString().trim() ?? '';
          final name = decoded['name']?.toString().trim() ?? '';
          final size = (decoded['size'] as num?)?.round() ?? 0;
          final duration = (decoded['duration'] as num?)?.round() ?? 0;
          final cover = decoded['cover']?.toString().trim() ?? '';
          if (url.isEmpty && name.isEmpty) return null;
          return VideoContent(
            url: url,
            name: name.isEmpty ? _nameFromUrl(url) : name,
            size: size,
            duration: duration < 0 ? 0 : duration,
            cover: cover,
          );
        }
      } catch (_) {}
    }
    if (isRemote(text)) {
      return VideoContent(url: text, name: _nameFromUrl(text), size: 0, duration: 0);
    }
    return null;
  }

  static bool isRemote(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  static String extensionOf(String name) {
    final slash = name.replaceAll('\\', '/');
    final base = slash.split('/').last;
    final dot = base.lastIndexOf('.');
    if (dot < 0 || dot == base.length - 1) return '';
    return base.substring(dot + 1).toLowerCase();
  }

  static bool isAllowed(String name) {
    return allowedExtensions.contains(extensionOf(name));
  }

  String get durationLabel {
    if (duration <= 0) return '';
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String _nameFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final name = path.replaceAll('\\', '/').split('/').last;
    return name.isEmpty ? '视频' : name;
  }
}
