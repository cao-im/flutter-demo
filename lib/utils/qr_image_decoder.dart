import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

String? decodeQrImage(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  try {
    final pixels = image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List();
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    final result = QRCodeReader().decode(BinaryBitmap(GlobalHistogramBinarizer(source)));
    final text = result.text.trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}
