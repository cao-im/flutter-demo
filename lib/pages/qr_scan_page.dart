import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/qr_actions.dart';
import '../utils/qr_image_decoder.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final TextEditingController _controller = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_busy) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;
    var bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && !kIsWeb && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      _toast('没有读到图片');
      return;
    }
    final text = decodeQrImage(bytes);
    if (text == null) {
      _toast('图片里没有识别到二维码');
      return;
    }
    await _submit(text);
  }

  Future<void> _submit(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await QrActions.handle(context, text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫一扫')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('选择一张包含 CaoIM 二维码的图片，或粘贴二维码内容。', style: TextStyle(fontSize: 14, height: 1.4)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _pickImage,
            icon: const Icon(Icons.image_outlined),
            label: const Text('从图片识别'),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: '二维码内容',
              hintText: 'caoim://u/用户号 或 caoim://g/群号',
              border: OutlineInputBorder(),
            ),
            onSubmitted: _submit,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : () => _submit(_controller.text),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('识别'),
          ),
        ],
      ),
    );
  }
}
