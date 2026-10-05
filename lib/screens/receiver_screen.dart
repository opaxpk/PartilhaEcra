import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/discovery.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'viewer_screen.dart';

/// Pede o código ao utilizador e abre o visualizador.
Future<void> connectToHost(
  BuildContext context, {
  required String ip,
  int port = kSignalPort,
  String? name,
}) async {
  final pin = await showDialog<String>(
    context: context,
    builder: (_) => _PinDialog(hostName: name ?? ip),
  );
  if (pin == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ViewerScreen(ip: ip, port: port, pin: pin, initialName: name ?? ip),
  ));
}

class ReceiverScreen extends StatelessWidget {
  const ReceiverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recetor', style: TextStyle(fontWeight: FontWeight.w700))),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: NearbyDevicesPanel(showSearchBanner: true, framed: false),
        ),
      ),
    );
  }
}

/// Lista de Hosts encontrados na rede + ligação manual por IP.
class NearbyDevicesPanel extends StatefulWidget {
  const NearbyDevicesPanel({super.key, this.showSearchBanner = false, this.framed = true});
  final bool showSearchBanner;
  final bool framed;

  @override
  State<NearbyDevicesPanel> createState() => _NearbyDevicesPanelState();
}

class _NearbyDevicesPanelState extends State<NearbyDevicesPanel> {
  final _listener = DiscoveryListener.instance;
  final _ipController = TextEditingController();
  StreamSubscription<List<DiscoveredDevice>>? _sub;
  List<DiscoveredDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _sub = _listener.stream.listen((d) {
      if (mounted) setState(() => _devices = d);
    });
    _listener.acquire().then((_) {
      if (mounted) setState(() => _devices = _listener.devices);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _listener.release();
    _ipController.dispose();
    super.dispose();
  }

  void _connectManual() {
    final ip = _ipController.text.trim();
    final valid = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip);
    if (!valid) {
      showSnack(context, 'Escreve um IP válido, por exemplo 192.168.1.10');
      return;
    }
    connectToHost(context, ip: ip);
  }

  @override
  Widget build(BuildContext context) {
    final sharing = _devices.where((d) => d.sharing).toList();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showSearchBanner) ...[
          Panel(
            child: Row(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.orange),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('À procura na rede…', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        sharing.isEmpty
                            ? 'Abre a PartilhaEcra no outro dispositivo e escolhe Host'
                            : '${sharing.length} ${sharing.length == 1 ? 'dispositivo encontrado' : 'dispositivos encontrados'}',
                        style: const TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        Row(
          children: [
            const Expanded(child: SectionLabel('Na tua rede')),
            if (_listener.scanning)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              TextButton(
                onPressed: () {
                  _listener.scanSubnet();
                  setState(() {});
                },
                child: const Text('Procurar de novo'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (_listener.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_listener.error!, style: const TextStyle(color: AppColors.dangerText, fontSize: 13)),
          ),
        Expanded(
          child: sharing.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Ainda não há ninguém a partilhar.\nSe o outro dispositivo já está em Host, usa o IP abaixo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: sharing.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _DeviceTile(device: sharing[i]),
                ),
        ),
        const SizedBox(height: 12),
        const Text('Não aparece? Liga por IP', style: TextStyle(fontSize: 13, color: AppColors.muted)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ipController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(hintText: '192.168.1.__', isDense: true),
                onSubmitted: (_) => _connectManual(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: AppColors.onOrange,
                minimumSize: const Size(80, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _connectManual,
              child: const Text('Ligar', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ],
    );
    if (!widget.framed) return content;
    return Panel(color: const Color(0xFF0E1626), radius: 20, padding: const EdgeInsets.all(20), child: content);
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});
  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => connectToHost(context, ip: device.ip, port: device.port, name: device.name),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
                child: Icon(platformIcon(device.platform), color: AppColors.text, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${device.platform} · ${device.link} · ${device.ip}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Pill('Ver', color: AppColors.onOrange, background: AppColors.orange),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.hostName});
  final String hostName;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _controller.text.trim();
    if (pin.length == 4) Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Ligar a ${widget.hostName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Escreve o código de 4 dígitos que aparece no ecrã do Host.',
              style: TextStyle(color: AppColors.muted, fontSize: 14)),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 12),
            decoration: const InputDecoration(counterText: '', hintText: '____'),
            onChanged: (v) {
              if (v.length == 4) _submit();
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Ligar')),
      ],
    );
  }
}
