import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<Uint8List> renderQrCardPng({
  required String data,
  required String title,
  required String subtitle,
}) async {
  const width = 720.0;
  const height = 960.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, width, height),
    Paint()..color = const Color(0xFFFFFFFF),
  );

  _paintCentered(
    canvas,
    text: title,
    style: const TextStyle(color: Color(0xFF191919), fontSize: 40, fontWeight: FontWeight.w600, height: 1.2),
    top: 56,
    width: width,
  );

  const qrSize = 520.0;
  final qrImage = await QrPainter(
    data: data,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF000000)),
  ).toImage(qrSize);
  canvas.drawImage(qrImage, const Offset((width - qrSize) / 2, 200), Paint());
  qrImage.dispose();

  _paintCentered(
    canvas,
    text: subtitle,
    style: const TextStyle(color: Color(0xFF888888), fontSize: 28, height: 1.3),
    top: 770,
    width: width,
  );

  final image = await recorder.endRecording().toImage(width.toInt(), height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null || bytes.lengthInBytes == 0) {
    throw StateError('二维码图片生成失败');
  }
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

void _paintCentered(
  Canvas canvas, {
  required String text,
  required TextStyle style,
  required double top,
  required double width,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: width - 96);
  painter.paint(canvas, Offset((width - painter.width) / 2, top));
  painter.dispose();
}

String qrDownloadName(String title) {
  final cleaned = title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '').trim();
  final base = cleaned.isEmpty ? 'caoim' : cleaned;
  final clipped = base.length > 40 ? base.substring(0, 40) : base;
  return '$clipped-二维码.png';
}
