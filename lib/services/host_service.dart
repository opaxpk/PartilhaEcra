import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config.dart';
import 'capture.dart';
import 'discovery.dart';
import 'native_bridge.dart';
import 'settings.dart';

/// Um recetor ligado a este Host.
class ReceiverSession {
  ReceiverSession(this.id, this.socket, this.address);

  final String id;
  final WebSocket socket;
  final String address;
  String name = 'Recetor';
  bool authorized = false;
  bool connected = false;
  double? rttMs;
  RTCPeerConnection? pc;
  final List<RTCRtpSender> senders = [];
  final List<RTCIceCandidate> pendingCandidates = [];
  bool remoteSet = false;
  Future<void> queue = Future.value();
}

/// Lado do Host: captura o ecrã, aceita recetores e envia-lhes o vídeo por WebRTC.
class HostService extends ChangeNotifier {
  HttpServer? _server;
  MediaStream? _stream;
  final _broadcaster = DiscoveryBroadcaster();
  Timer? _statsTimer;
  bool _disposed = false;

  final List<ReceiverSession> _pending = [];
  final List<ReceiverSession> receivers = [];

  bool running = false;
  bool starting = false;
  String pin = '----';
  String? error;
  StreamQuality quality = AppSettings.quality;
  int fps = AppSettings.fps;
  String sourceLabel = '';

  Future<void> start({DesktopCapturerSource? source}) async {
    if (running || starting) return;
    starting = true;
    error = null;
    _notify();
    try {
      pin = (Random.secure().nextInt(9000) + 1000).toString();
      _stream = await CaptureHelper.captureScreen(source: source, fps: fps);
      sourceLabel = source?.name ?? (Platform.isAndroid ? 'Ecrã do telemóvel' : 'Ecrã principal');

      final tracks = _stream!.getVideoTracks();
      if (tracks.isNotEmpty) {
        tracks.first.onEnded = () => stop();
      }

      _server = await HttpServer.bind(InternetAddress.anyIPv4, kSignalPort);
      _server!.listen(_handleRequest, onError: (_) {});
      await _broadcaster.start();
      _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) => _collectStats());
      running = true;
    } on CaptureCancelled {
      await _cleanup();
    } on SocketException catch (e) {
      error = 'A porta $kSignalPort está ocupada (outra instância aberta?). ${e.message}';
      await _cleanup();
    } catch (e) {
      error = 'Não foi possível iniciar a partilha: $e';
      await _cleanup();
    } finally {
      starting = false;
      _notify();
    }
  }

  Future<void> _handleRequest(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response
        ..statusCode = HttpStatus.ok
        ..write('PartilhaEcra Host')
        ..close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    final session = ReceiverSession(
      DateTime.now().microsecondsSinceEpoch.toString(),
      ws,
      req.connectionInfo?.remoteAddress.address ?? '?',
    );
    _pending.add(session);
    ws.listen(
      (data) {
        session.queue = session.queue.then((_) => _onMessage(session, data)).catchError((_) {});
      },
      onDone: () => _removeSession(session),
      onError: (_) => _removeSession(session),
      cancelOnError: true,
    );
    // Quem não se identificar em 60 s é desligado.
    Timer(const Duration(seconds: 60), () {
      if (!session.authorized) _closeSocket(session);
    });
  }

  Future<void> _onMessage(ReceiverSession s, dynamic data) async {
    if (data is! String) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'hello':
        s.name = (msg['name'] ?? 'Recetor').toString();
        if (msg['pin']?.toString() != pin) {
          _send(s, {'type': 'rejected', 'reason': 'Código de ligação errado.'});
          await Future<void>.delayed(const Duration(milliseconds: 300));
          _closeSocket(s);
          return;
        }
        if (receivers.length >= kMaxReceivers) {
          _send(s, {'type': 'rejected', 'reason': 'Limite de $kMaxReceivers recetores atingido.'});
          await Future<void>.delayed(const Duration(milliseconds: 300));
          _closeSocket(s);
          return;
        }
        s.authorized = true;
        _pending.remove(s);
        receivers.add(s);
        _notify();
        _send(s, {
          'type': 'accepted',
          'hostName': AppSettings.deviceName,
          'platform': AppSettings.platformName,
          'source': sourceLabel,
        });
        await _startPeer(s);
        break;
      case 'answer':
        if (!s.authorized || s.pc == null) return;
        await s.pc!.setRemoteDescription(RTCSessionDescription(msg['sdp'] as String?, 'answer'));
        s.remoteSet = true;
        for (final c in s.pendingCandidates) {
          await s.pc!.addCandidate(c);
        }
        s.pendingCandidates.clear();
        await _applyEncoding(s);
        break;
      case 'candidate':
        if (!s.authorized) return;
        final c = RTCIceCandidate(
          msg['candidate'] as String?,
          msg['sdpMid'] as String?,
          (msg['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (s.remoteSet && s.pc != null) {
          await s.pc!.addCandidate(c);
        } else {
          s.pendingCandidates.add(c);
        }
        break;
      case 'bye':
        _removeSession(s);
        break;
    }
  }

  Future<void> _startPeer(ReceiverSession s) async {
    final stream = _stream;
    if (stream == null) return;
    final pc = await createPeerConnection(<String, dynamic>{
      'iceServers': <dynamic>[],
      'sdpSemantics': 'unified-plan',
    });
    s.pc = pc;
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _send(s, {
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        s.connected = true;
        _notify();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _removeSession(s);
      }
    };
    for (final track in stream.getTracks()) {
      s.senders.add(await pc.addTrack(track, stream));
    }
    final offer = await pc.createOffer(<String, dynamic>{});
    await pc.setLocalDescription(offer);
    _send(s, {'type': 'offer', 'sdp': offer.sdp});
  }

  /// Aplica débito máximo, fps e escala de acordo com a qualidade escolhida.
  Future<void> _applyEncoding(ReceiverSession s) async {
    for (final sender in s.senders) {
      if (sender.track?.kind != 'video') continue;
      try {
        final params = sender.parameters;
        final encodings = params.encodings;
        final enc = (encodings == null || encodings.isEmpty) ? RTCRtpEncoding() : encodings.first;
        enc.maxBitrate = quality.maxBitrate;
        enc.maxFramerate = Platform.isAndroid ? 30 : fps;
        enc.scaleResolutionDownBy = quality.scaleDown;
        params.encodings = [enc];
        await sender.setParameters(params);
      } catch (e) {
        debugPrint('setParameters falhou: $e');
      }
    }
  }

  Future<void> setQuality(StreamQuality q) async {
    quality = q;
    await AppSettings.setQuality(q);
    for (final s in receivers) {
      await _applyEncoding(s);
    }
    _notify();
  }

  Future<void> setFps(int value) async {
    fps = value;
    await AppSettings.setFps(value);
    _notify();
  }

  Future<void> _collectStats() async {
    for (final s in List<ReceiverSession>.from(receivers)) {
      final pc = s.pc;
      if (pc == null) continue;
      try {
        final reports = await pc.getStats();
        for (final r in reports) {
          if (r.type == 'candidate-pair' &&
              (r.values['state'] == 'succeeded' || r.values['nominated'] == true)) {
            final rtt = _num(r.values['currentRoundTripTime']);
            if (rtt != null) s.rttMs = rtt * 1000;
          }
        }
      } catch (_) {}
    }
    if (receivers.isNotEmpty) _notify();
  }

  void kick(ReceiverSession s) {
    _send(s, {'type': 'kicked'});
    Future<void>.delayed(const Duration(milliseconds: 200), () => _removeSession(s));
  }

  void _send(ReceiverSession s, Map<String, dynamic> msg) {
    try {
      s.socket.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _closeSocket(ReceiverSession s) {
    try {
      s.socket.close();
    } catch (_) {}
  }

  void _removeSession(ReceiverSession s) {
    _pending.remove(s);
    final removed = receivers.remove(s);
    final pc = s.pc;
    s.pc = null;
    pc?.close();
    _closeSocket(s);
    if (removed) _notify();
  }

  Future<void> stop() async {
    if (!running && !starting) return;
    for (final s in List<ReceiverSession>.from(receivers)) {
      _send(s, {'type': 'bye'});
      _removeSession(s);
    }
    for (final s in List<ReceiverSession>.from(_pending)) {
      _removeSession(s);
    }
    await _cleanup();
    running = false;
    _notify();
  }

  Future<void> _cleanup() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    await _broadcaster.stop();
    await _server?.close(force: true);
    _server = null;
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final t in stream.getTracks()) {
        try {
          await t.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }
    await NativeBridge.stopCaptureService();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    super.dispose();
  }
}

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
