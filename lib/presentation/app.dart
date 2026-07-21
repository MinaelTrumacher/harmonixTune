import 'package:flutter/material.dart';
import '../domain/repositories/tuning_profile_repository.dart';
import 'theme/app_theme.dart';
import 'navigation/main_shell.dart';

class HarmonixTuneApp extends StatelessWidget {
  const HarmonixTuneApp({super.key, required this.tuningProfileRepository});

  final TuningProfileRepository tuningProfileRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'harmonixTune',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: MainShell(tuningProfileRepository: tuningProfileRepository),
    );
  }
}
