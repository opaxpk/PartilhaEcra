import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.currentVersion,
    required this.notes,
    required this.downloadUrl,
    required this.size,
  });

  final String version;
  final String currentVersion;
  final String notes;
  final String downloadUrl;
  final int size;
}

/// Atualizações a partir das Releases do GitHub.
///
/// Android: descarrega o novo APK e abre o instalador do sistema (o Android pede
/// sempre uma confirmação ao utilizador — não é possível instalar em silêncio).
/// Windows: descarrega o instalador, corre-o em modo silencioso, fecha a app e
/// o instalador volta a abri-la já atualizada.
class Updater {
  static const _apiUrl = 'https://api.github.com/repos/$kGithubRepo/releases/latest';

  static Future<String> currentVersion() async => (await PackageInfo.fromPlatform()).version;

  /// Devolve a atualização disponível, ou null se já estiver na última versão.
  static Future<UpdateInfo?> check() async {
    final res = await http.get(Uri.parse(_apiUrl), headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'PartilhaEcra-Updater',
    }).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('GitHub respondeu ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final latest = (json['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '');
    final current = await currentVersion();
    if (latest.isEmpty || !isNewer(latest, current)) return null;

    final suffix = Platform.isAndroid ? '.apk' : '-Setup.exe';
    final assets = (json['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
    final asset = assets.where((a) => (a['name'] as String? ?? '').endsWith(suffix)).firstOrNull;
    if (asset == null) return null;

    return UpdateInfo(
      version: latest,
      currentVersion: current,
      notes: (json['body'] as String? ?? '').trim(),
      downloadUrl: asset['browser_download_url'] as String,
      size: (asset['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// Compara versões no formato 1.2.3.
  static bool isNewer(String candidate, String current) {
    List<int> parse(String v) =>
        v.split(RegExp(r'[.+-]')).take(3).map((e) => int.tryParse(e) ?? 0).toList();
    final a = parse(candidate), b = parse(current);
    while (a.length < 3) {
      a.add(0);
    }
    while (b.length < 3) {
      b.add(0);
    }
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static Future<File> download(UpdateInfo info, void Function(double progress) onProgress) async {
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(info.downloadUrl)));
      if (res.statusCode != 200) throw Exception('Download falhou (${res.statusCode})');
      final dir = await getTemporaryDirectory();
      final name = Platform.isAndroid ? 'PartilhaEcra-update.apk' : 'PartilhaEcra-Setup.exe';
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      if (await file.exists()) await file.delete();
      final sink = file.openWrite();
      final total = res.contentLength ?? info.size;
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }

  static Future<void> install(File file) async {
    if (Platform.isAndroid) {
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        throw Exception(
          'Não foi possível abrir o instalador (${result.message}). '
          'Permite "Instalar apps desconhecidas" para a PartilhaEcra nas definições do Android.',
        );
      }
      return;
    }
    if (Platform.isWindows) {
      await Process.start(
        file.path,
        ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      // Fecha a app para o instalador poder substituir os ficheiros.
      exit(0);
    }
    throw UnsupportedError('Atualização automática não suportada nesta plataforma.');
  }
}
