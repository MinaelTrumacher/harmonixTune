class ChordResult {
  const ChordResult({
    required this.chordName,
    required this.chromaVector,
    required this.confidence,
    required this.activeNoteIndices,
  });

  final String chordName;
  final List<double> chromaVector; // 12 valeurs normalisées [0.0–1.0]
  final double confidence;
  final Set<int> activeNoteIndices;

  static const ChordResult silent = ChordResult(
    chordName: '--',
    chromaVector: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    confidence: 0,
    activeNoteIndices: {},
  );
}
