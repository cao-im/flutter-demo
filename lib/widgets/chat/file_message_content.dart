import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';

import '../../models/file_content.dart';
import '../../models/message_model.dart';

class FileMessageContent extends StatelessWidget {
  final MessageModel message;

  const FileMessageContent({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final file = FileContent.tryParse(message.content);
    final name = file?.name.isNotEmpty == true ? file!.name : '文件';
    final size = file?.sizeLabel ?? '';
    final ext = FileContent.extensionOf(name);
    return Material(
      color: AppTheme.bubbleIncoming(context),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: message.status == MessageStatus.sending ? null : () => _open(context, file),
        child: Container(
          width: 230,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, height: 1.3, color: AppTheme.textPrimary(context)),
                    ),
                    if (size.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(size, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context))),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _FileIcon(ext: ext),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, FileContent? file) async {
    final url = (file?.url ?? message.mediaUrl ?? '').trim();
    if (url.isEmpty) {
      _toast(context, '文件地址无效');
      return;
    }
    final uri = url.startsWith('http://') || url.startsWith('https://') ? Uri.parse(url) : Uri.file(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _toast(context, '无法打开这个文件');
    }
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _FileIcon extends StatelessWidget {
  final String ext;

  const _FileIcon({required this.ext});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (ext) {
      'pdf' => (Icons.picture_as_pdf, const Color(0xFFE35D5D)),
      'doc' || 'docx' => (Icons.description, const Color(0xFF4C8DFF)),
      'xls' || 'xlsx' => (Icons.table_chart, const Color(0xFF3DAA6D)),
      'ppt' || 'pptx' => (Icons.slideshow, const Color(0xFFE08A3C)),
      'zip' || 'rar' => (Icons.folder_zip, const Color(0xFF8A7A5A)),
      'mp3' || 'wav' || 'm4a' || 'aac' || 'amr' || 'ogg' || 'opus' => (Icons.audio_file, const Color(0xFF7A6BB5)),
      'mp4' || 'avi' || 'mov' => (Icons.video_file, const Color(0xFF5B7C99)),
      'jpg' || 'jpeg' || 'png' || 'gif' || 'bmp' || 'webp' => (Icons.image, const Color(0xFF5B8FA8)),
      _ => (Icons.insert_drive_file, const Color(0xFF8C8C8C)),
    };
    return Icon(icon, size: 36, color: color);
  }
}
