import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/home_screen.dart';
import 'services/crash_report.dart';
import 'services/device_profile.dart';
import 'services/settings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.init();
  await CrashReport.checkAtStartup();
  await DeviceProfile.init();
  if (DeviceProfile.isTv) {
    // Projetor/TV: o contorno do item selecionado aparece logo, sem esperar por uma tecla.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  }

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      size: const Size(1180, 760),
      minimumSize: const Size(420, 640),
      center: true,
      title: 'PartilhaEcra',
      backgroundColor: AppColors.bg,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const PartilhaEcraApp());
}

class PartilhaEcraApp extends StatelessWidget {
  const PartilhaEcraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PartilhaEcra',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}
