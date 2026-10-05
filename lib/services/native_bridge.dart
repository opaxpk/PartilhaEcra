import 'dart:io';

import 'package:flutter/services.dart';

/// Ponte para o código nativo Android (serviço em primeiro plano e multicast).
class NativeBridge {
  static const _channel = MethodChannel('partilhaecra/native');

  /// Inicia o serviço em primeiro plano exigido pelo Android para capturar o ecrã.
  static Future<void> startCaptureService() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('startCaptureService');
  }

  static Future<void> stopCaptureService() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopCaptureService');
    } catch (_) {}
  }

  /// Sem este "lock" muitos telemóveis ignoram os pacotes de descoberta por Wi-Fi.
  static Future<void> acquireMulticastLock() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('acquireMulticastLock');
    } catch (_) {}
  }

  static Future<void> releaseMulticastLock() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('releaseMulticastLock');
    } catch (_) {}
  }
}
