import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../navigation/app_route.dart';
import '../models/favorite_item.dart';
import '../models/message_model.dart';
import '../providers/favorite_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/chat/video_message_content.dart';

class FavoritesPage extends StatefulWidget {
  final bool embedded;

  const FavoritesPage({super.key, this.embedded = false});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FavoriteProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    const body = _FavoriteList();
    if (widget.embedded) {
      return Material(color: AppTheme.surface(context), child: body);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: body,
    );
  }
}

class _FavoriteList extends StatelessWidget {
  const _FavoriteList();

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoriteProvider>(
      builder: (context, provider, _) {
        if (provider.loading && provider.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_outline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text('还没有收藏', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary(context))),
                const SizedBox(height: 4),
                Text('在聊天里长按消息，选择收藏', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context))),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: provider.load,
          child: ListView.separated(
            itemCount: provider.items.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
            itemBuilder: (context, index) {
              final item = provider.items[index];
              final selected = provider.selected?.id == item.id;
              return Material(
                color: selected ? AppTheme.primaryColor.withValues(alpha: 0.08) : Colors.transparent,
                child: ListTile(
                  leading: Icon(_iconFor(item.type), color: AppTheme.textSecondary(context)),
                  title: Text(item.preview, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${item.senderLabel} · ${item.sourceLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    provider.select(item);
                    final embedded = context.findAncestorWidgetOfExactType<FavoritesPage>()?.embedded ?? false;
                    if (!embedded) {
                      Navigator.push(
                        context,
                        AppRoute(builder: (_) => FavoriteDetailPage(item: item)),
                      );
                    }
                  },
                  onLongPress: () => _confirmRemove(context, item),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _confirmRemove(BuildContext context, FavoriteItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消收藏'),
        content: const Text('从收藏夹里移出这条内容？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('移出')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<FavoriteProvider>().remove(item.id);
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, _messageOf(error));
    }
  }
}

class FavoriteDetailPane extends StatelessWidget {
  const FavoriteDetailPane({super.key});

  @override
  Widget build(BuildContext context) {
    final item = context.watch<FavoriteProvider>().selected;
    if (item == null) {
      return Material(
        color: AppTheme.background(context),
        child: Center(
          child: Text('选择一条收藏查看', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary(context))),
        ),
      );
    }
    return FavoriteDetailView(item: item);
  }
}

class FavoriteDetailPage extends StatelessWidget {
  final FavoriteItem item;

  const FavoriteDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final current = context.watch<FavoriteProvider>().items.cast<FavoriteItem?>().firstWhere(
          (entry) => entry?.id == item.id,
          orElse: () => null,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: current == null
          ? const Center(child: Text('这条收藏已移出'))
          : FavoriteDetailView(item: current),
    );
  }
}

class FavoriteDetailView extends StatelessWidget {
  final FavoriteItem item;

  const FavoriteDetailView({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.background(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.senderLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        '${item.sourceLabel}  ${_formatTime(item.messageTime)}',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _remove(context),
                  child: const Text('移出'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _body(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (item.type) {
      case MessageType.image:
        final url = item.imageUrl;
        if (url == null) return const Text('图片已失效');
        return Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('图片加载失败'));
      case MessageType.file:
        final file = item.file;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file?.name.isNotEmpty == true ? file!.name : '文件', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: file == null || file.url.isEmpty ? null : () => _openUrl(context, file.url),
              child: const Text('打开文件'),
            ),
          ],
        );
      case MessageType.video:
        final video = item.video;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (video != null && video.cover.isNotEmpty)
              Image.network(video.cover, height: 180, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: video == null || video.url.isEmpty
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        AppRoute(builder: (_) => VideoPlayPage(source: video.url)),
                      );
                    },
              child: const Text('播放视频'),
            ),
          ],
        );
      case MessageType.audio:
        return Text(item.preview, style: const TextStyle(fontSize: 16));
      case MessageType.text:
      case MessageType.notice:
        return SelectableText(item.content, style: const TextStyle(fontSize: 16, height: 1.5));
    }
  }

  Future<void> _remove(BuildContext context) async {
    try {
      await context.read<FavoriteProvider>().remove(item.id);
      if (context.mounted && Navigator.of(context).canPop()) {
        final page = context.findAncestorWidgetOfExactType<FavoriteDetailPage>();
        if (page != null) Navigator.of(context).pop();
      }
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, _messageOf(error));
    }
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _showMessage(context, '无法打开这个文件');
    }
  }
}

IconData _iconFor(MessageType type) {
  switch (type) {
    case MessageType.image:
      return Icons.image_outlined;
    case MessageType.file:
      return Icons.insert_drive_file_outlined;
    case MessageType.audio:
      return Icons.mic_none;
    case MessageType.video:
      return Icons.videocam_outlined;
    case MessageType.text:
    case MessageType.notice:
      return Icons.chat_bubble_outline;
  }
}

String _formatTime(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _messageOf(Object error) {
  return error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
}

void _showMessage(BuildContext context, String text) {
  if (context.findAncestorWidgetOfExactType<Scaffold>() == null) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
