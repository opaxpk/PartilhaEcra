import 'dart:io';

import 'package:flutter/material.dart';

import '../config.dart';
import '../services/crash_report.dart';
import '../services/device_profile.dart';
import '../services/settings.dart';
import '../services/updater.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/crash_dialog.dart';
import '../widgets/update_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _name = TextEditingController(text: AppSettings.deviceName);
  String _version = '';
  bool _checking = false;
  bool _autoUpdates = AppSettings.autoCheckUpdates;
  String _decoderMode = AppSettings.decoderMode;
  int _audioDelay = AppSettings.audioDelayMs;
  bool _lowLatency = AppSettings.lowLatency;

  @override
  void initState() {
    super.initState();
    Updater.currentVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await AppSettings.setDeviceName(_name.text);
    if (mounted) showSnack(context, 'Nome guardado.');
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    await checkForUpdates(context, silent: false);
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Definições', style: TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                const SectionLabel('Nome deste dispositivo'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        maxLength: 40,
                        decoration: const InputDecoration(counterText: '', isDense: true),
                        onSubmitted: (_) => _saveName(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _saveName, child: const Text('Guardar')),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('É o nome que os outros veem na lista de dispositivos.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 28),
                if (Platform.isAndroid) ...[
                  const SectionLabel('Descodificação de vídeo'),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'auto', label: Text('Automático')),
                      ButtonSegment(value: 'hw', label: Text('Hardware (exp.)')),
                      ButtonSegment(value: 'sw', label: Text('Software')),
                    ],
                    selected: {_decoderMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (sel) {
                      AppSettings.setDecoderMode(sel.first);
                      setState(() => _decoderMode = sel.first);
                      showSnack(context, 'Fecha e volta a abrir a app para aplicar.');
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Em uso: ${DeviceProfile.modeLabel}. Software funciona em todos os aparelhos. '
                    'Hardware é mais leve, mas em alguns projetores dá imagem verde/riscada ou fecha a app.',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 28),
                  Panel(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Latência mínima'),
                      subtitle: const Text(
                        'Mostra cada imagem logo que chega. Desliga se o vídeo der pequenos saltos. '
                        'Reinicia a app para aplicar.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                      value: _lowLatency,
                      onChanged: (v) {
                        AppSettings.setLowLatency(v);
                        setState(() => _lowLatency = v);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('Atraso do som'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _audioDelay.toDouble(),
                          min: 0,
                          max: 600,
                          divisions: 12,
                          label: '$_audioDelay ms',
                          onChanged: (v) => setState(() => _audioDelay = v.round()),
                          onChangeEnd: (v) => AppSettings.setAudioDelayMs(v.round()),
                        ),
                      ),
                      SizedBox(width: 64, child: Text('$_audioDelay ms', textAlign: TextAlign.end)),
                    ],
                  ),
                  const Text(
                    'Se o som chegar antes da imagem, aumenta. Aplica-se na próxima ligação.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 28),
                ],
                const SectionLabel('Atualizações'),
                const SizedBox(height: 8),
                Panel(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Procurar atualizações ao abrir'),
                    subtitle: const Text('Avisa quando há uma versão nova no GitHub',
                        style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    value: _autoUpdates,
                    onChanged: (v) {
                      AppSettings.setAutoCheckUpdates(v);
                      setState(() => _autoUpdates = v);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _checking ? null : _check,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: _checking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.system_update_alt),
                  label: const Text('Verificar atualizações agora'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final report = await CrashReport.lastReport();
                    if (!context.mounted) return;
                    if (report == null) {
                      showSnack(context, 'Não há relatórios de erro.');
                    } else {
                      await showCrashReportDialog(context, report, fresh: false);
                    }
                  },
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: const Text('Ver último relatório de erro'),
                ),
                const SizedBox(height: 20),
                const SectionLabel('Sobre'),
                const SizedBox(height: 8),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PartilhaEcra ${_version.isEmpty ? '' : 'v$_version'}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const SelectableText('github.com/$kGithubRepo',
                          style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      const SizedBox(height: 4),
                      const Text('Portas usadas: UDP $kDiscoveryPort (descoberta) e TCP $kSignalPort (ligação).',
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
