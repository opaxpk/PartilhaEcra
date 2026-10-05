import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/crash_report.dart';
import '../services/device_profile.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/crash_dialog.dart';
import '../widgets/update_dialog.dart';
import 'host_screen.dart';
import 'receiver_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startupChecks());
  }

  Future<void> _startupChecks() async {
    final report = CrashReport.pending;
    CrashReport.pending = null;
    if (report != null && mounted) {
      await showCrashReportDialog(context, report, compatEnabled: CrashReport.enabledCompat);
    }
    if (AppSettings.autoCheckUpdates && mounted) await checkForUpdates(context);
  }

  void _openHost() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HostScreen()));

  void _openReceiver() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReceiverScreen()));

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    if (mounted) setState(() {});
  }

  Widget _header() {
    return Row(
      children: [
        const AppLogo(),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('PartilhaEcra',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        ),
        IconButton.outlined(
          tooltip: 'Definições',
          onPressed: _openSettings,
          style: IconButton.styleFrom(
            side: const BorderSide(color: AppColors.border),
            backgroundColor: AppColors.surface,
            minimumSize: const Size(44, 44),
          ),
          icon: const Icon(Icons.settings_outlined, color: AppColors.muted, size: 20),
        ),
      ],
    );
  }

  Widget _modes({required bool wide}) {
    final host = ModeCard(
      title: 'Host',
      subtitle: 'Partilhar o ecrã deste dispositivo',
      icon: Icons.upload_rounded,
      color: AppColors.accent,
      onColor: AppColors.onAccent,
      highlighted: true,
      autofocus: DeviceProfile.isTv,
      onTap: _openHost,
      footer: wide ? 'Atalho: Ctrl + Shift + H' : null,
    );
    final receiver = ModeCard(
      title: 'Recetor',
      subtitle: 'Ver o ecrã de outro dispositivo',
      icon: Icons.download_rounded,
      color: AppColors.orange,
      onColor: AppColors.onOrange,
      onTap: _openReceiver,
      footer: wide ? 'Atalho: Ctrl + Shift + R' : null,
    );
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: host),
          const SizedBox(width: 16),
          Expanded(child: receiver),
        ],
      );
    }
    return Column(children: [host, const SizedBox(height: 16), receiver]);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyH, control: true, shift: true): _openHost,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true, shift: true): _openReceiver,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                if (wide) return _wideLayout();
                return _narrowLayout();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _narrowLayout() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        _header(),
        const SizedBox(height: 24),
        const NetworkBanner(),
        const SizedBox(height: 24),
        const Text('O que queres fazer?',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.15)),
        const SizedBox(height: 6),
        const Text('Os dois dispositivos têm de estar na mesma rede (Wi-Fi ou cabo).',
            style: TextStyle(fontSize: 15, color: AppColors.muted)),
        const SizedBox(height: 24),
        _modes(wide: false),
        const SizedBox(height: 24),
        Row(
          children: [
            const Text('Este dispositivo: ', style: TextStyle(fontSize: 13, color: AppColors.muted)),
            Expanded(
              child: Text(AppSettings.deviceName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: _openSettings, child: const Text('Mudar nome')),
          ],
        ),
      ],
    );
  }

  Widget _wideLayout() {
    return Column(
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(32, 20, 32, 0), child: _header()),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Partilha o ecrã em segundos',
                                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1)),
                            const SizedBox(height: 8),
                            const Text('Escolhe um modo. Os dispositivos na mesma rede aparecem sozinhos.',
                                style: TextStyle(fontSize: 16, color: AppColors.muted)),
                            const SizedBox(height: 24),
                            _modes(wide: true),
                            const SizedBox(height: 24),
                            const NetworkBanner(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),
                    const Expanded(flex: 2, child: NearbyDevicesPanel()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
