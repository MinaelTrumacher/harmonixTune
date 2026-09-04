/// Qualité d'accord reconnue par le détecteur (US3) — 4 qualités × 12
/// racines = 48 templates. [intervals] sont exprimés en demi-tons depuis la
/// fondamentale (convention MIDI `C=0`, cf. `NoteFrequencyConverter`).
enum ChordQuality {
  major(intervals: [0, 4, 7], suffix: ''),
  minor(intervals: [0, 3, 7], suffix: 'm'),
  dominant7(intervals: [0, 4, 7, 10], suffix: '7'),
  major7(intervals: [0, 4, 7, 11], suffix: 'maj7');

  const ChordQuality({required this.intervals, required this.suffix});

  final List<int> intervals;
  final String suffix;
}
