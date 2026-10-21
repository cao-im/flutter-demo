import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart' as sdk;
import 'package:flutter/foundation.dart';

import '../models/chat_file_item.dart';
import '../models/chat_model.dart';
import '../models/file_content.dart';
import '../models/message_model.dart';
import '../models/video_content.dart';
import '../sdk/im_sdk_manager.dart';

enum FileKindFilter { all, image, video, file }

class FileLibraryProvider extends ChangeNotifier {
  final IMSdkManager _sdk = IMSdkManager();

  List<ChatFileItem> _items = [];
  FileKindFilter _filter = FileKindFilter.all;
  String _keyword = '';
  ChatFileItem? _selected;
  bool _loading = false;

  List<ChatFileItem> get items => _visible();
  FileKindFilter get filter => _filter;
  String get keyword => _keyword;
  ChatFileItem? get selected => _selected;
  bool get loading => _loading;
  bool get hasAny => _items.isNotEmpty;

  Future<void> load(List<ConversationModel> conversations) async {
    _loading = true;
    notifyListeners();
    try {
      final me = _sdk.client.currentUserId ?? 0;
      final messages = await _sdk.client.listMediaMessages();
      final groups = <int, ConversationModel>{};
      final peers = <int, ConversationModel>{};
      for (final conversation in conversations) {
        if (conversation.targetId <= 0) continue;
        if (conversation.isGroup) {
          groups[conversation.targetId] = conversation;
        } else {
          peers[conversation.targetId] = conversation;
        }
      }
      final seen = <String>{};
      final next = <ChatFileItem>[];
      for (final message in messages) {
        final item = _toItem(message, me: me, groups: groups, peers: peers);
        if (item == null || !seen.add(item.key)) continue;
        next.add(item);
      }
      _items = next;
      if (_selected != null && !_items.any((item) => item.key == _selected!.key)) {
        _selected = null;
      }
    } catch (error) {
      debugPrint('加载聊天文件失败: $error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setFilter(FileKindFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    notifyListeners();
  }

  void setKeyword(String value) {
    if (_keyword == value) return;
    _keyword = value;
    notifyListeners();
  }

  void select(ChatFileItem? item) {
    if (_selected?.key == item?.key) return;
    _selected = item;
    notifyListeners();
  }

  List<ChatFileItem> _visible() {
    final text = _keyword.trim().toLowerCase();
    return _items.where((item) {
      if (_filter == FileKindFilter.image && item.type != MessageType.image) return false;
      if (_filter == FileKindFilter.video && item.type != MessageType.video) return false;
      if (_filter == FileKindFilter.file && item.type != MessageType.file) return false;
      if (text.isEmpty) return true;
      return item.name.toLowerCase().contains(text) ||
          item.conversationName.toLowerCase().contains(text) ||
          item.senderName.toLowerCase().contains(text);
    }).toList();
  }

  ChatFileItem? _toItem(
    sdk.Message message, {
    required int me,
    required Map<int, ConversationModel> groups,
    required Map<int, ConversationModel> peers,
  }) {
    if (message.status == sdk.MessageStatus.recalled) return null;
    final type = switch (message.msgType) {
      sdk.MessageType.image => MessageType.image,
      sdk.MessageType.video => MessageType.video,
      sdk.MessageType.file => MessageType.file,
      _ => null,
    };
    if (type == null) return null;

    final groupId = message.groupId ?? 0;
    final isGroup = groupId > 0;
    final peer = message.fromId == me ? message.toId : message.fromId;
    final targetId = isGroup ? groupId : peer;
    if (targetId <= 0) return null;

    final conversation = isGroup ? groups[targetId] : peers[targetId];
    final sender = message.fromId == me
        ? '我'
        : (message.senderNickname?.trim().isNotEmpty == true
            ? message.senderNickname!.trim()
            : (message.senderInfo?.nickname.trim().isNotEmpty == true
                ? message.senderInfo!.nickname.trim()
                : '用户${message.fromId}'));
    final conversationName = conversation?.name.trim().isNotEmpty == true
        ? conversation!.name.trim()
        : (isGroup
            ? (message.groupInfo?.groupName.trim().isNotEmpty == true
                ? message.groupInfo!.groupName.trim()
                : '群聊$targetId')
            : (message.fromId == me ? '用户$peer' : sender));

    final parsed = _describe(type, message.content);
    final key = message.midKey ?? 'l${message.id ?? message.timestamp}';
    return ChatFileItem(
      key: key,
      type: type,
      name: parsed.$1,
      url: parsed.$2,
      size: parsed.$3,
      time: DateTime.fromMillisecondsSinceEpoch(message.timestamp),
      targetId: targetId,
      isGroup: isGroup,
      conversationName: conversationName,
      senderName: sender,
      content: message.content,
    );
  }

  (String, String, int) _describe(MessageType type, String content) {
    if (type == MessageType.video) {
      final video = VideoContent.tryParse(content);
      final name = video?.name.trim().isNotEmpty == true ? video!.name.trim() : '视频';
      return (name, video?.url ?? '', video?.size ?? 0);
    }
    if (type == MessageType.file) {
      final file = FileContent.tryParse(content);
      final name = file?.name.trim().isNotEmpty == true ? file!.name.trim() : '文件';
      return (name, file?.url ?? '', file?.size ?? 0);
    }
    final text = content.trim();
    if (text.startsWith('http://') || text.startsWith('https://')) {
      return (_nameFromUrl(text), text, 0);
    }
    final file = FileContent.tryParse(text);
    if (file != null) {
      return (file.name.isEmpty ? '图片' : file.name, file.url, file.size);
    }
    return ('图片', text, 0);
  }

  String _nameFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final name = path.replaceAll('\\', '/').split('/').last;
    if (name.isEmpty || name.length > 80) return '图片';
    return name;
  }
}
