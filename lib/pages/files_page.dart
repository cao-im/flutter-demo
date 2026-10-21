import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_file_item.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../providers/chat_provider.dart';
import '../providers/file_library_provider.dart';
import '../providers/layout_provider.dart';
import '../router/app_router.dart';
import '../services/chat_file_opener.dart';
import '../services/media_store.dart';
import '../theme/app_theme.dart';
import '../widgets/chat/video_message_content.dart';

class FilesPage extends StatefulWidget {
  final bool embedded;

  const FilesPage({super.key, this.embedded = false});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final chat = context.read<ChatProvider>();
    final library = context.read<FileLibraryProvider>();
    await library.load(chat.conversations);
    chat.cacheStoredFiles(library.storedItems);
  }

  @override
  Widget build(BuildContext context) {
    final body = _FileLibraryBody(embedded: widget.embedded, onRefresh: _reload);
    if (widget.embedded) {
      return Material(color: AppTheme.surface(context), child: body);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('聊天文件')),
      body: body,
    );
  }
}

class _FileLibraryBody extends StatelessWidget {
  final bool embedded;
  final Future<void> Function() onRefresh;

  const _FileLibraryBody({required this.embedded, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Consumer<FileLibraryProvider>(
      builder: (context, library, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: '搜索文件名或会话',
                  border: OutlineInputBorder(),
                ),
                onChanged: library.setKeyword,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _FilterChip(label: '全部', value: FileKindFilter.all, selected: library.filter),
                  _FilterChip(label: '图片', value: FileKindFilter.image, selected: library.filter),
                  _FilterChip(label: '视频', value: FileKindFilter.video, selected: library.filter),
                  _FilterChip(label: '文件', value: FileKindFilter.file, selected: library.filter),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(child: _list(context, library)),
          ],
        );
      },
    );
  }

  Widget _list(BuildContext context, FileLibraryProvider library) {
    if (library.loading && !library.hasAny) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!library.hasAny) {
      return _empty(context, '还没有聊天文件', '聊天里发送或收到的图片、视频和文件会出现在这里');
    }
    final visible = library.items;
    if (visible.isEmpty) {
      return _empty(context, '没有匹配的文件', '换个关键词或类型看看');
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        itemCount: visible.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
        itemBuilder: (context, index) {
          final item = visible[index];
          final selected = library.selected?.key == item.key;
          return Material(
            color: selected ? AppTheme.primaryColor.withValues(alpha: 0.08) : Colors.transparent,
            child: ListTile(
              leading: Icon(_iconFor(item.type), color: AppTheme.textSecondary(context)),
              title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${item.conversationName} · ${_formatTime(item.time)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                library.select(item);
                if (!embedded) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FileDetailPage(item: item)),
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 14, color: AppTheme.textSecondary(context))),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final FileKindFilter value;
  final FileKindFilter selected;

  const _FilterChip({required this.label, required this.value, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected == value,
        onSelected: (_) => context.read<FileLibraryProvider>().setFilter(value),
      ),
    );
  }
}

class FileDetailPane extends StatelessWidget {
  const FileDetailPane({super.key});

  @override
  Widget build(BuildContext context) {
    final item = context.watch<FileLibraryProvider>().selected;
    if (item == null) {
      return Material(
        color: AppTheme.background(context),
        child: Center(
          child: Text('选择一个文件查看', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary(context))),
        ),
      );
    }
    return FileDetailView(item: item);
  }
}

class FileDetailPage extends StatelessWidget {
  final ChatFileItem item;

  const FileDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final current = context.watch<FileLibraryProvider>().items.cast<ChatFileItem?>().firstWhere(
          (entry) => entry?.key == item.key,
          orElse: () => item,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('聊天文件')),
      body: FileDetailView(item: current ?? item),
    );
  }
}

class FileDetailView extends StatelessWidget {
  final ChatFileItem item;

  const FileDetailView({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.background(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  '${item.conversationName} · ${item.senderName} · ${_formatTime(item.time)}'
                  '${item.sizeLabel.isEmpty ? '' : ' · ${item.sizeLabel}'}',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                ),
                const SizedBox(height: 8),
                _LocalLocation(item: item),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _preview(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: item.url.trim().isEmpty && item.localPath.trim().isEmpty ? null : () => _open(context),
                  child: const Text('打开'),
                ),
                OutlinedButton(
                  onPressed: () => _reveal(context),
                  child: const Text('打开所在位置'),
                ),
                OutlinedButton(
                  onPressed: () => _openConversation(context),
                  child: const Text('在聊天中查看'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final imageSource = item.localPath.trim().isNotEmpty ? item.localPath.trim() : item.url.trim();
    if (item.type == MessageType.image && imageSource.isNotEmpty) {
      return InteractiveViewer(
        child: MediaStore.image(imageSource, error: _placeholder(context, '图片无法显示')),
      );
    }
    if (item.type == MessageType.video) {
      return Align(
        alignment: Alignment.topCenter,
        child: VideoMessageContent(
          message: MessageModel(
            id: item.key,
            conversationId: '${item.targetId}',
            senderId: '',
            receiverId: '',
            type: MessageType.video,
            content: item.content,
            mediaUrl: item.url,
            timestamp: item.time,
            localPath: item.localPath.isEmpty ? null : item.localPath,
            midKey: item.key,
          ),
        ),
      );
    }
    return _placeholder(context, item.typeLabel);
  }

  Widget _placeholder(BuildContext context, String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(item.type), size: 56, color: AppTheme.textSecondary(context)),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(color: AppTheme.textSecondary(context))),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    await ChatFileOpener.open(
      context,
      name: item.name,
      remoteUrl: item.url,
      localPath: item.localPath,
      messageKey: item.key,
    );
  }

  Future<void> _reveal(BuildContext context) async {
    final folder = await MediaStore.folder();
    final path = item.localPath.trim().isNotEmpty ? item.localPath.trim() : folder;
    final opened = await MediaStore.reveal(path);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(folder.isEmpty ? '网页端会用浏览器打开原文件' : '文件目录：$folder')),
      );
    }
  }

  void _openConversation(BuildContext context) {
    final chat = context.read<ChatProvider>();
    chat.focusMessage(item.key);
    final existing = chat.conversations.cast<ConversationModel?>().firstWhere(
          (entry) => entry != null && entry.targetId == item.targetId && entry.isGroup == item.isGroup,
          orElse: () => null,
        );
    final conversation = existing ??
        ConversationModel(
          id: '${item.targetId}',
          targetId: item.targetId,
          name: item.conversationName,
          participantIds: const [],
          isGroup: item.isGroup,
        );
    chat.setCurrentConversation(conversation);
    final embedded = context.findAncestorWidgetOfExactType<FilesPage>()?.embedded;
    if (embedded == true) {
      context.read<LayoutProvider>().openConversation(
            conversation.id,
            conversation.name,
            conversation.isGroup,
          );
      return;
    }
    Navigator.pushNamed(
      context,
      AppRouter.chat,
      arguments: {
        'conversationId': conversation.id,
        'conversationName': conversation.name,
        'isGroup': conversation.isGroup,
        'targetId': conversation.targetId,
      },
    );
  }
}

class _LocalLocation extends StatelessWidget {
  final ChatFileItem item;

  const _LocalLocation({required this.item});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, height: 1.4, color: AppTheme.textSecondary(context));
    return FutureBuilder<String>(
      future: MediaStore.folder(),
      builder: (context, snapshot) {
        final folder = snapshot.data ?? '';
        final saved = item.localPath.trim();
        if (folder.isEmpty && saved.isEmpty) {
          return Text('网页端会用浏览器打开，文件留在浏览器的下载记录里。', style: style);
        }
        final where = saved.isNotEmpty ? saved : (folder.isEmpty ? '' : '$folder（打开后保存到这里）');
        if (where.isEmpty) return const SizedBox.shrink();
        return Text('本机位置：$where', style: style);
      },
    );
  }
}

IconData _iconFor(MessageType type) {
  switch (type) {
    case MessageType.image:
      return Icons.image_outlined;
    case MessageType.video:
      return Icons.video_file_outlined;
    case MessageType.file:
      return Icons.insert_drive_file_outlined;
    default:
      return Icons.folder_outlined;
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
