import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

Future<void> showCrashReportDialog(
  BuildContext context,
  String report, {
  bool fresh = true,
  bool compatEnabled = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(fresh ? 'A app fechou inesperadamente' : 'Último relatório de erro'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compatEnabled)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'O erro veio do descodificador de vídeo deste aparelho. Liguei o modo de '
                  'compatibilidade de vídeo — já está ativo, podes tentar de novo.',
                  style: TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            if (fresh)
              const Text(
                'Copia este relatório e envia-o para ajudar a corrigir o problema.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bgDeep,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    report,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.text),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar')),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: report));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Relatório copiado.')),
              );
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copiar relatório'),
        ),
      ],
    ),
  );
}
