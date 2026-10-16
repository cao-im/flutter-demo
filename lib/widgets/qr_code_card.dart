import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/auth_provider.dart';
import '../utils/qr_card_image.dart';
import '../utils/qr_payload.dart';
import '../utils/qr_png_saver.dart';

Future<void> showMyQrCode(BuildContext context) {
  final user = context.read<AuthProvider>().user;
  final id = int.tryParse(user?.imUserId ?? user?.id ?? '') ?? 0;
  if (id <= 0) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text('暂时无法生成二维码'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('关闭')),
        ],
      ),
    );
  }
  final name = user?.nickname.isNotEmpty == true
      ? user!.nickname
      : (user?.username.isNotEmpty == true ? user!.username : '我');
  return showQrCodeDialog(
    context,
    data: QrPayload.user(id),
    title: name,
    subtitle: '扫一扫上面的二维码，加我为好友',
  );
}

Future<void> showQrCodeDialog(
  BuildContext context, {
  required String data,
  required String title,
  required String subtitle,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _QrCodeDialog(data: data, title: title, subtitle: subtitle),
  );
}

class _QrCodeDialog extends StatefulWidget {
  final String data;
  final String title;
  final String subtitle;

  const _QrCodeDialog({required this.data, required this.title, required this.subtitle});

  @override
  State<_QrCodeDialog> createState() => _QrCodeDialogState();
}

class _QrCodeDialogState extends State<_QrCodeDialog> {
  var _saving = false;
  String? _status;
  var _statusOk = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      final bytes = await renderQrCardPng(
        data: widget.data,
        title: widget.title,
        subtitle: widget.subtitle,
      );
      final saved = await saveQrPng(bytes, qrDownloadName(widget.title));
      if (!mounted) return;
      if (saved) {
        setState(() {
          _status = '二维码已保存';
          _statusOk = true;
        });
      }
    } catch (error) {
      if (!mounted) return;
      final text = error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
      setState(() {
        _status = '保存失败：$text';
        _statusOk = false;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            QrImageView(
              data: widget.data,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 12),
            Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF888888)),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _statusOk ? const Color(0xFF07C160) : const Color(0xFFE64340),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存图片'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }
}
