import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_search_hit.dart';
import '../models/user_model.dart';
import '../providers/chat_provider.dart';
import '../providers/contact_provider.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';

class ChatSearchResults extends StatelessWidget {
  final String keyword;
  final List<ChatSearchHit> hits;
  final bool searching;
  final void Function(String id, String name, bool isGroup, int targetId) onOpen;

  const ChatSearchResults({
    super.key,
    required this.keyword,
    required this.hits,
    required this.searching,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final text = keyword.trim().toLowerCase();
    final contacts = context.watch<ContactProvider>().contacts.where((contact) {
      return contact.displayName.toLowerCase().contains(text) ||
          contact.username.toLowerCase().contains(text);
    }).take(8).toList();
    final groups = context.watch<ChatProvider>().conversations.where((conversation) {
      return conversation.isGroup && conversation.name.toLowerCase().contains(text);
    }).take(8).toList();
    final histories = _groupHits(context, text);

    if (contacts.isEmpty && groups.isEmpty && histories.isEmpty) {
      if (searching) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text('没有找到“$keyword”', style: TextStyle(fontSize: 15, color: Colors.grey[600])),
      );
    }

    return ListView(
      children: [
        if (contacts.isNotEmpty) ...[
          const _SectionTitle('联系人'),
          for (final contact in contacts)
            _ResultRow(
              name: contact.displayName,
              avatar: contact.avatar,
              subtitle: contact.username,
              onTap: () => _openContact(contact),
            ),
        ],
        if (groups.isNotEmpty) ...[
          const _SectionTitle('群聊'),
          for (final group in groups)
            _ResultRow(
              name: group.name,
              avatar: group.avatar,
              subtitle: '群聊',
              onTap: () => onOpen(group.id, group.name, true, group.targetId),
            ),
        ],
        if (histories.isNotEmpty || searching) ...[
          const _SectionTitle('聊天记录'),
          if (searching && histories.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          for (final item in histories)
            _ResultRow(
              name: item.title,
              avatar: item.avatar,
              subtitle: item.count > 1 ? '${item.count}条相关聊天记录' : item.snippet,
              onTap: () => onOpen(item.id, item.title, item.isGroup, item.targetId),
            ),
        ],
      ],
    );
  }

  void _openContact(UserModel contact) {
    final targetId = int.tryParse(contact.imUserId ?? contact.id) ?? int.tryParse(contact.id) ?? 0;
    if (targetId <= 0) return;
    onOpen('$targetId', contact.displayName, false, targetId);
  }

  List<_HistoryItem> _groupHits(BuildContext context, String keyword) {
    final chat = context.read<ChatProvider>();
    final contacts = context.read<ContactProvider>().contacts;
    final grouped = <String, _HistoryItem>{};
    for (final hit in hits) {
      if (hit.targetId <= 0) continue;
      final key = '${hit.isGroup}:${hit.targetId}';
      final existing = grouped[key];
      if (existing != null) {
        existing.count += 1;
        continue;
      }
      grouped[key] = _HistoryItem(
        id: '${hit.targetId}',
        targetId: hit.targetId,
        isGroup: hit.isGroup,
        title: _title(chat, contacts, hit),
        avatar: _avatar(chat, contacts, hit),
        snippet: _snippet(hit.message.displayText, keyword),
      );
    }
    return grouped.values.take(20).toList();
  }

  String _title(ChatProvider chat, List<UserModel> contacts, ChatSearchHit hit) {
    for (final conversation in chat.conversations) {
      if (conversation.isGroup == hit.isGroup && conversation.targetId == hit.targetId) {
        if (conversation.name.isNotEmpty) return conversation.name;
      }
    }
    if (!hit.isGroup) {
      for (final contact in contacts) {
        final id = int.tryParse(contact.imUserId ?? contact.id) ?? int.tryParse(contact.id);
        if (id == hit.targetId) return contact.displayName;
      }
      final sender = hit.message.senderDisplayName;
      if (sender.isNotEmpty) return sender;
      return '用户${hit.targetId}';
    }
    return '群聊 ${hit.targetId}';
  }

  String? _avatar(ChatProvider chat, List<UserModel> contacts, ChatSearchHit hit) {
    for (final conversation in chat.conversations) {
      if (conversation.isGroup == hit.isGroup && conversation.targetId == hit.targetId) {
        return conversation.avatar;
      }
    }
    if (!hit.isGroup) {
      for (final contact in contacts) {
        final id = int.tryParse(contact.imUserId ?? contact.id) ?? int.tryParse(contact.id);
        if (id == hit.targetId) return contact.avatar;
      }
    }
    return hit.message.senderDisplayAvatar;
  }

  String _snippet(String content, String keyword) {
    final text = content.replaceAll('\n', ' ').trim();
    if (text.isEmpty) return '';
    final lower = text.toLowerCase();
    final index = lower.indexOf(keyword);
    if (index < 0) {
      return text.length > 36 ? '${text.substring(0, 36)}…' : text;
    }
    final start = index > 10 ? index - 10 : 0;
    final end = index + keyword.length + 18;
    final clippedEnd = end < text.length ? end : text.length;
    final prefix = start > 0 ? '…' : '';
    final suffix = clippedEnd < text.length ? '…' : '';
    return '$prefix${text.substring(start, clippedEnd)}$suffix';
  }
}

class _HistoryItem {
  final String id;
  final int targetId;
  final bool isGroup;
  final String title;
  final String? avatar;
  final String snippet;
  int count = 1;

  _HistoryItem({
    required this.id,
    required this.targetId,
    required this.isGroup,
    required this.title,
    required this.avatar,
    required this.snippet,
  });
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF7F7F7),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(text, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context))),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String name;
  final String? avatar;
  final String subtitle;
  final VoidCallback onTap;

  const _ResultRow({
    required this.name,
    required this.avatar,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AvatarWidget(imageUrl: avatar, name: name, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: AppTheme.textPrimary(context)),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
