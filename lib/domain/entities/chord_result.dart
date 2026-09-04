class ChordResult {
  const ChordResult({
    required this.chordName,
    required this.familyName,
    required this.chromaVector,
    required this.confidence,
    required this.activeNoteIndices,
  });

  final String chordName;
  // Triade de base (racine + majeur/mineur, sans 7e) que ce chordName
  // partage avec ses variantes structurelles — ex. "F", "F7" et "Fmaj7" ont
  // tous familyName "F" ; "Fm" est sa propre famille. Sert au vote pondéré
  // du ChordSmoother (cf. docs/STRATEGIE_DETECTION_ACCORDS.md §13).
  final String familyName;
  final List<double> chromaVector; // 12 valeurs normalisées [0.0–1.0]
  final double confidence;
  final Set<int> activeNoteIndices;

  static const ChordResult silent = ChordResult(
    chordName: '--',
    familyName: '--',
    chromaVector: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    confidence: 0,
    activeNoteIndices: {},
  );
}
