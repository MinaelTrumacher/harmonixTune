import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'navigation/main_shell.dart';

class HarmonixTuneApp extends StatelessWidget {
  const HarmonixTuneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'harmonixTune',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const MainShell(),
    );
  }
}
