class QrPayload {
  final bool isUser;
  final int id;

  const QrPayload._({required this.isUser, required this.id});

  static String user(int id) => 'caoim://u/$id';

  static String group(int id) => 'caoim://g/$id';

  static QrPayload? parse(String raw) {
    final text = raw.trim();
    final match = RegExp(r'^caoim://([ug])/(\d+)$').firstMatch(text);
    if (match == null) return null;
    final id = int.tryParse(match.group(2) ?? '');
    if (id == null || id <= 0) return null;
    return QrPayload._(isUser: match.group(1) == 'u', id: id);
  }
}
