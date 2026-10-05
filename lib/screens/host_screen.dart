import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/capture.dart';
import '../services/host_service.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HostScreen extends StatefulWidget {
  const HostScreen({super.key});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  final _host = HostService();
  DesktopCapturerSource? _source;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await _host.start(source: _source);
    if (!mounted) return;
    if (_host.error != null) showSnack(context, _host.error!);
  }

  Future<void> _pickSource() async {
    final source = await showDialog<DesktopCapturerSource>(
      context: context,
      builder: (_) => const _SourcePickerDialog(),
    );
    if (source != null && mounted) setState(() => _source = source);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _host,
      builder: (context, _) {
        final running = _host.running;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Host', style: TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              if (running)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: AppColors.onAccent),
                      SizedBox(width: 6),
                      Text('EM DIRETO',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onAccent)),
                    ],
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: running ? _runningView() : _setupView(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _qualitySelector() {
    return SegmentedButton<StreamQuality>(
      segments: StreamQuality.values
          .map((q) => ButtonSegment<StreamQuality>(value: q, label: Text(q.label)))
          .toList(),
      selected: {_host.quality},
      showSelectedIcon: false,
      onSelectionChanged: (s) => _host.setQuality(s.first),
    );
  }

  Widget _setupView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const NetworkBanner(),
        const SizedBox(height: 24),
        const SectionLabel('Qualidade'),
        const SizedBox(height: 8),
        _qualitySelector(),
        const SizedBox(height: 6),
        Text(
          switch (_host.quality) {
            StreamQuality.auto => 'Ajusta-se sozinha à rede. Recomendado.',
            StreamQuality.economy => 'Menos resolução e dados. Boa para Wi-Fi fraco.',
            StreamQuality.max => 'Máxima nitidez. Ideal com cabo de rede.',
          },
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        if (Platform.isWindows) ...[
          const SizedBox(height: 20),
          const SectionLabel('Fluidez'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 30, label: Text('30 fps')),
              ButtonSegment(value: 60, label: Text('60 fps')),
            ],
            selected: {_host.fps},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _host.setFps(s.first),
          ),
          const SizedBox(height: 20),
          const SectionLabel('O que partilhar'),
          const SizedBox(height: 8),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                Icon(_source?.type == SourceType.Window ? Icons.web_asset : Icons.monitor,
                    color: AppColors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_source?.name ?? 'Ecrã principal',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
                TextButton(onPressed: _pickSource, child: const Text('Escolher')),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _host.starting ? null : _start,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: _host.starting
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent))
              : const Icon(Icons.screen_share_outlined),
          label: const Text('Começar a partilhar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        Text(
          Platform.isAndroid
              ? 'O Android vai pedir autorização para gravar o ecrã. Depois podes sair da app: a partilha continua.'
              : 'Na primeira vez o Windows pode pedir para permitir a app na firewall — aceita para "Redes privadas".',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        if (_host.error != null) ...[
          const SizedBox(height: 12),
          Text(_host.error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.dangerText)),
        ],
      ],
    );
  }

  Widget _runningView() {
    final receivers = _host.receivers;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Panel(
          radius: 20,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text('Código de ligação', style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(height: 4),
              SelectableText(_host.pin,
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: 10)),
              const SizedBox(height: 4),
              const Text('O recetor tem de introduzir este código para ver o teu ecrã',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.muted)),
              if (_host.localIps.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(
                  'Se não aparecer na lista, liga por IP: ${_host.localIps.join('  ou  ')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: StatTile(value: _host.quality.label, label: 'Qualidade')),
            const SizedBox(width: 10),
            Expanded(child: StatTile(value: '${Platform.isAndroid ? 30 : _host.fps} fps', label: 'Fluidez')),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: '${receivers.length}/4',
                label: 'Recetores',
                valueColor: receivers.isEmpty ? AppColors.text : AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionLabel('Recetores ligados'),
        const SizedBox(height: 8),
        if (receivers.isEmpty)
          const Panel(
            child: Text('À espera de alguém… No outro dispositivo escolhe Recetor e toca neste dispositivo.',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
        for (final r in receivers) ...[
          Panel(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            radius: 14,
            child: Row(
              children: [
                const Icon(Icons.devices, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      Text(r.connected ? r.address : 'A ligar… ${r.address}',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                if (r.rttMs != null) Pill('${r.rttMs!.round()} ms'),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _host.kick(r),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerText,
                    side: const BorderSide(color: Color(0xFF4A2A33)),
                  ),
                  child: const Text('Expulsar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        const SectionLabel('Qualidade'),
        const SizedBox(height: 8),
        _qualitySelector(),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => _host.stop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Parar partilha', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _SourcePickerDialog extends StatefulWidget {
  const _SourcePickerDialog();

  @override
  State<_SourcePickerDialog> createState() => _SourcePickerDialogState();
}

class _SourcePickerDialogState extends State<_SourcePickerDialog> {
  List<DesktopCapturerSource>? _sources;
  String? _error;

  @override
  void initState() {
    super.initState();
    CaptureHelper.desktopSources().then((s) {
      if (mounted) setState(() => _sources = s);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('O que queres partilhar?'),
      content: SizedBox(
        width: 640,
        height: 420,
        child: _error != null
            ? Text(_error!)
            : sources == null
                ? const Center(child: CircularProgressIndicator())
                : GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.25,
                    children: [
                      for (final s in sources)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(context).pop(s),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: AppColors.bgDeep,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: s.thumbnail != null
                                      ? Image.memory(s.thumbnail!, fit: BoxFit.contain, gaplessPlayback: true)
                                      : Icon(s.type == SourceType.Screen ? Icons.monitor : Icons.web_asset,
                                          color: AppColors.muted),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                s.type == SourceType.Screen ? 'Ecrã: ${s.name}' : s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
      ],
    );
  }
}
