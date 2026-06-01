import 'package:flutter/material.dart';
import '../screens/tuner/tuner_screen.dart';
import '../screens/presets/presets_screen.dart';
import '../screens/chords/chords_screen.dart';
import '../theme/app_colors.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const List<Widget> _screens = [
    TunerScreen(),
    PresetsScreen(),
    ChordsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: 'Tuner'),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music_outlined),
            label: 'Presets',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.piano_outlined),
            label: 'Chords',
          ),
        ],
      ),
    );
  }
}
