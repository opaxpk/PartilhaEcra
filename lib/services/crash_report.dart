import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'native_bridge.dart';
import 'updater.dart';

/// Gera um relatório quando a app fechou inesperadamente da última vez (Android).
class CrashReport {
  static const _kLastSeen = 'crashLastSeenExit';
  static const _kLastReport = 'crashLastReport';

  // Constantes de ApplicationExitInfo.REASON_*
  static const _reasonNames = {
    1: 'Saiu sozinha (exit)',
    2: 'Terminada por sinal do sistema',
    3: 'Pouca memória (o Android fechou a app)',
    4: 'Erro (crash Java/Kotlin)',
    5: 'Erro nativo (crash C/C++)',
    6: 'Sem resposta (ANR)',
    7: 'Falha a iniciar',
    8: 'Permissão alterada',
    9: 'Uso excessivo de recursos',
    10: 'Fechada pelo utilizador',
    11: 'Utilizador parado',
    12: 'Dependência terminou',
    13: 'Outro motivo',
    14: 'Congelada pelo sistema',
    15: 'Estado do pacote alterado',
    16: 'App atualizada',
  };

  /// Motivos que indicam um fecho inesperado.
  static const _badReasons = {2, 3, 4, 5, 6, 7, 9, 13, 14};

  /// Último relatório gerado (para ver nas Definições).
  static Future<String?> lastReport() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastReport);
  }

  /// Devolve um relatório novo, ou null se a app não fechou inesperadamente.
  static Future<String?> checkPending() async {
    if (!Platform.isAndroid) return null;
    final data = await NativeBridge.crashReport();
    if (data == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getInt(_kLastSeen) ?? 0;

    final exits = (data['exits'] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .toList();
    var newest = lastSeen;
    final fresh = <Map<dynamic, dynamic>>[];
    for (final e in exits) {
      final ts = (e['timestamp'] as num?)?.toInt() ?? 0;
      if (ts > newest) newest = ts;
      if (ts > lastSeen && _badReasons.contains((e['reason'] as num?)?.toInt())) fresh.add(e);
    }
    await prefs.setInt(_kLastSeen, newest);

    final javaCrash = data['javaCrash'] as String?;
    if (fresh.isEmpty && (javaCrash == null || javaCrash.isEmpty)) return null;

    final b = StringBuffer()
      ..writeln('PartilhaEcra ${await Updater.currentVersion()} — relatório de erro')
      ..writeln('Dispositivo: ${data['device']} · Android ${data['android']}');
    for (final e in fresh) {
      final ts = DateTime.fromMillisecondsSinceEpoch((e['timestamp'] as num).toInt());
      final reason = (e['reason'] as num?)?.toInt() ?? 0;
      b
        ..writeln()
        ..writeln('Quando: $ts')
        ..writeln('Motivo: ${_reasonNames[reason] ?? reason} (código $reason, estado ${e['status']})')
        ..writeln('Importância: ${e['importance']} · Memória: ${((e['pssKb'] as num?) ?? 0) ~/ 1024} MB');
      final desc = (e['description'] as String?) ?? '';
      if (desc.isNotEmpty) b.writeln('Descrição: $desc');
      final trace = e['trace'] as String?;
      if (trace != null && trace.isNotEmpty) {
        b
          ..writeln('Trace:')
          ..writeln(trace);
      }
    }
    if (javaCrash != null && javaCrash.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Erro:')
        ..writeln(javaCrash);
    }
    final report = b.toString().trim();
    await prefs.setString(_kLastReport, report);
    return report;
  }
}
