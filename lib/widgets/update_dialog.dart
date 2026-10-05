import 'dart:io';

import 'package:flutter/material.dart';

import '../services/settings.dart';
import '../services/updater.dart';
import '../theme.dart';

/// Verifica atualizações e mostra o diálogo se houver uma nova versão.
/// [silent] = true não mostra nada quando não há atualização ou ocorre erro.
Future<void> checkForUpdates(BuildContext context, {bool silent = true}) async {
  UpdateInfo? info;
  try {
    info = await Updater.check();
  } catch (e) {
    if (!silent && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível verificar atualizações: $e')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  if (info == null) {
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Já tens a versão mais recente.')),
      );
    }
    return;
  }
  if (silent && AppSettings.skippedVersion == info.version) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDialog(info: info!),
  );
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info});
  final UpdateInfo info;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double? _progress;
  bool _busy = false;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final file = await Updater.download(widget.info, (p) {
        if (mounted) setState(() => _progress = p);
      });
      await Updater.install(file);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final sizeMb = info.size > 0 ? ' · ${(info.size / 1048576).toStringAsFixed(1)} MB' : '';
    final notes = info.notes.length > 600 ? '${info.notes.substring(0, 600)}…' : info.notes;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Nova versão disponível'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${info.currentVersion} → ${info.version}$sizeMb',
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.accent)),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(notes, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              Platform.isAndroid
                  ? 'A app descarrega a atualização e o Android pede-te para confirmar a instalação.'
                  : 'A app descarrega a atualização, instala-a e volta a abrir sozinha.',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(
                _progress == null ? 'A preparar…' : 'A descarregar… ${((_progress ?? 0) * 100).round()}%',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.dangerText, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        if (!_busy)
          TextButton(
            onPressed: () {
              AppSettings.setSkippedVersion(info.version);
              Navigator.of(context).pop();
            },
            child: const Text('Ignorar versão'),
          ),
        if (!_busy)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Mais tarde'),
          ),
        FilledButton(
          onPressed: _busy ? null : _update,
          child: Text(_error == null ? 'Atualizar agora' : 'Tentar de novo'),
        ),
      ],
    );
  }
}
