import 'dart:convert';

/// 语音消息内容：`{"url":"...","duration":秒}`。
class VoiceContent {
  final String url;
  final int duration;

  const VoiceContent({required this.url, required this.duration});

  static String encode(String url, int duration) {
    final seconds = duration < 1 ? 1 : (duration > 60 ? 60 : duration);
    return jsonEncode({'url': url, 'duration': seconds});
  }

  static VoiceContent? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map && decoded['url'] is String) {
          final url = (decoded['url'] as String).trim();
          if (url.isEmpty) return null;
          final duration = (decoded['duration'] as num?)?.round() ?? 1;
          return VoiceContent(
            url: url,
            duration: duration < 1 ? 1 : duration,
          );
        }
      } catch (_) {}
    }
    if (text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.contains('/') ||
        text.contains('\\')) {
      return VoiceContent(url: text, duration: 1);
    }
    return null;
  }
}
