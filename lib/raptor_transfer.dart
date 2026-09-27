import 'dart:convert';
import 'package:flutter/services.dart';

class RaptorTransfer {
  static const channel = MethodChannel('qrcodeapp/raptorq');
  static const prefix = 'RQ1:';
  static const frameBytes = 356;

  static String qrText(Uint8List bytes) {
    if (bytes.length != frameBytes) throw const FormatException('流水码帧长度无效');
    return '$prefix${base64Encode(bytes)}';
  }

  static Uint8List? parseQr(String value) {
    if (!value.startsWith(prefix) || value.length > 500) return null;
    try {
      final bytes = base64Decode(value.substring(prefix.length));
      return bytes.length == frameBytes && qrText(bytes) == value
          ? bytes
          : null;
    } on FormatException {
      return null;
    }
  }

  static Future<void> keepAwake(bool enabled) =>
      channel.invokeMethod<void>('keepAwake', {'enabled': enabled});
  static Future<void> resetReceiver() =>
      channel.invokeMethod<void>('resetReceiver');
  static Future<void> clearSender() =>
      channel.invokeMethod<void>('clearSender');
  static Future<Map<Object?, Object?>?> pickFile() =>
      channel.invokeMapMethod('pickFile');
  static Future<Map<Object?, Object?>?> createText(String text) =>
      channel.invokeMapMethod('createText', {'text': text});
  static Future<Uint8List?> nextFrame() =>
      channel.invokeMethod<Uint8List>('nextFrame');
  static Future<Map<Object?, Object?>?> accept(Uint8List bytes) =>
      channel.invokeMapMethod('acceptFrame', {'bytes': bytes});
  static Future<bool> save() async =>
      await channel.invokeMethod<bool>('saveReceived') ?? false;
}
