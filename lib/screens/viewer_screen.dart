import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../services/receiver_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.ip,
    required this.port,
    required this.pin,
    required this.initialName,
  });

  final String ip;
  final int port;
  final String pin;
  final String initialName;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final ReceiverService _rx = ReceiverService(ip: widget.ip, port: widget.port, pin: widget.pin);
  bool _fullscreen = false;
  bool _showBar = true;

  @override
  void initState() {
    super.initState();
    _rx.connect();
  }

  @override
  void dispose() {
    if (_fullscreen) _setFullscreen(false);
    _rx.dispose();
    super.dispose();
  }

  Future<void> _setFullscreen(bool value) async {
    if (Platform.isWindows) {
      await windowManager.setFullScreen(value);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
    if (mounted) {
      setState(() {
        _fullscreen = value;
        _showBar = true;
      });
    }
  }

  Future<void> _screenshot() async {
    try {
      final buffer = await _rx.captureFrame();
      if (buffer == null) return;
      Directory? dir;
      if (Platform.isWindows) {
        dir = await getDownloadsDirectory();
      } else if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      }
      dir ??= await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${dir.path}${Platform.pathSeparator}PartilhaEcra-$stamp.png');
      await file.writeAsBytes(buffer.asUint8List());
      if (mounted) showSnack(context, 'Imagem guardada em ${file.path}');
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível capturar a imagem: $e');
    }
  }

  Future<void> _disconnect() async {
    await _rx.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): () => _setFullscreen(!_fullscreen),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_fullscreen) _setFullscreen(false);
        },
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: _rx,
          builder: (context, _) => Scaffold(
            backgroundColor: AppColors.bgDeep,
            body: SafeArea(
              top: !_fullscreen,
              bottom: !_fullscreen,
              child: Column(
                children: [
                  if (_showBar) _toolbar(),
                  Expanded(child: _body()),
                  if (!_fullscreen && _rx.status == ReceiverStatus.playing)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12, top: 4),
                      child: Text('F11 ecrã completo · Esc sair do ecrã completo · toca no vídeo para esconder a barra',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    final name = _rx.hostName.isNotEmpty ? _rx.hostName : widget.initialName;
    final playing = _rx.status == ReceiverStatus.playing;
    // Resolução "p" = lado mais curto (um telemóvel na vertical 1080×2400 é 1080p).
    final res = (_rx.width != null && _rx.height != null)
        ? '${_rx.width! < _rx.height! ? _rx.width : _rx.height}p'
        : null;
    final fps = _rx.fps != null ? '${_rx.fps!.round()} fps' : null;
    final mbps = _rx.mbps != null ? '${_rx.mbps!.toStringAsFixed(1)} Mbps' : null;
    final details = [res, fps, mbps].whereType<String>().join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0E1626),
        border: Border(bottom: BorderSide(color: Color(0xFF1A2438))),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Voltar',
                onPressed: _disconnect,
                icon: const Icon(Icons.arrow_back, size: 20),
              ),
              Icon(Icons.circle, size: 8, color: playing ? AppColors.danger : AppColors.muted),
              const SizedBox(width: 8),
              Text('A ver: $name', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              if (_rx.latencyMs != null) Pill('${_rx.latencyMs!.round()} ms'),
              if (details.isNotEmpty) ...[
                const SizedBox(width: 8),
                Pill(details, color: AppColors.muted, background: AppColors.surface),
              ],
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolButton(
                tooltip: 'Capturar imagem',
                icon: Icons.photo_camera_outlined,
                onPressed: playing ? _screenshot : null,
              ),
              const SizedBox(width: 8),
              _ToolButton(
                tooltip: _fullscreen ? 'Sair do ecrã completo' : 'Ecrã completo',
                icon: _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                onPressed: () => _setFullscreen(!_fullscreen),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _disconnect,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Desligar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_rx.status) {
      case ReceiverStatus.connecting:
      case ReceiverStatus.waitingVideo:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _rx.status == ReceiverStatus.connecting ? 'A ligar a ${widget.ip}…' : 'A receber o ecrã…',
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        );
      case ReceiverStatus.ended:
      case ReceiverStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _rx.status == ReceiverStatus.error ? Icons.error_outline : Icons.info_outline,
                  size: 40,
                  color: _rx.status == ReceiverStatus.error ? AppColors.dangerText : AppColors.muted,
                ),
                const SizedBox(height: 12),
                Text(_rx.message ?? '', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
              ],
            ),
          ),
        );
      case ReceiverStatus.playing:
        return GestureDetector(
          onTap: () => setState(() => _showBar = !_showBar),
          onDoubleTap: () => _setFullscreen(!_fullscreen),
          child: Container(
            color: Colors.black,
            child: RTCVideoView(
              _rx.renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
    }
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tooltip, required this.icon, required this.onPressed});
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        minimumSize: const Size(40, 40),
      ),
      icon: Icon(icon, size: 18),
    );
  }
}
