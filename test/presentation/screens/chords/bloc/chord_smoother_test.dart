import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/domain/entities/chord_result.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_smoother.dart';

ChordResult makeChord({
  required String chordName,
  double confidence = 0.9,
}) => ChordResult(
  chordName: chordName,
  chromaVector: const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  confidence: confidence,
  activeNoteIndices: const {},
);

void main() {
  group('ChordSmoother — silence', () {
    test('silence → état silent immédiat, sans hold', () {
      final smoother = ChordSmoother();
      final result = smoother.push(ChordResult.silent);
      expect(result.kind, SmoothedChordKind.silent);
      expect(result.result.chordName, '--');
    });

    test('silence réinitialise le dernier accord confirmé (pas de hold après)', () {
      final smoother = ChordSmoother();
      // Confirme "C" (2/3 requis avec windowSize par défaut = 3).
      smoother.push(makeChord(chordName: 'C'));
      final confirmed = smoother.push(makeChord(chordName: 'C'));
      expect(confirmed.kind, SmoothedChordKind.detected);

      smoother.push(ChordResult.silent);

      // Un accord isolé et différent juste après le silence ne doit PAS
      // afficher "C" en hold — il n'y a plus rien à tenir.
      final afterSilence = smoother.push(makeChord(chordName: 'G'));
      expect(afterSilence.kind, SmoothedChordKind.indeterminate);
    });
  });

  group('ChordSmoother — majorité et hold (§5.2 du cadrage US3)', () {
    test('séquence complète : indétermination initiale → majorité → hold → '
        'bascule finale sur indéterminé', () {
      final smoother = ChordSmoother();

      // 1) Un seul "C" : pas encore de majorité (2/3 requis), rien à tenir.
      final r1 = smoother.push(makeChord(chordName: 'C'));
      expect(r1.kind, SmoothedChordKind.indeterminate);

      // 2) 2e "C" consécutif → majorité atteinte (2/3).
      final r2 = smoother.push(makeChord(chordName: 'C'));
      expect(r2.kind, SmoothedChordKind.detected);
      expect(r2.result.chordName, 'C');

      // 3) "G" isolé : la fenêtre contient encore 2×C + 1×G → "C" reste
      //    majoritaire (inertie de la fenêtre glissante).
      final r3 = smoother.push(makeChord(chordName: 'G'));
      expect(r3.kind, SmoothedChordKind.detected);
      expect(r3.result.chordName, 'C');

      // 4) "Am" : la fenêtre glisse à [G, Am] + ce nouvel élément → plus de
      //    majorité → hold 1/2, "C" reste affiché.
      final r4 = smoother.push(makeChord(chordName: 'Am'));
      expect(r4.kind, SmoothedChordKind.detected);
      expect(r4.result.chordName, 'C');

      // 5) "Dm" : toujours pas de majorité → hold 2/2, "C" tenu encore.
      final r5 = smoother.push(makeChord(chordName: 'Dm'));
      expect(r5.kind, SmoothedChordKind.detected);
      expect(r5.result.chordName, 'C');

      // 6) "Em" : hold épuisé → bascule sur indéterminé.
      final r6 = smoother.push(makeChord(chordName: 'Em'));
      expect(r6.kind, SmoothedChordKind.indeterminate);
    });

    test('confiance sous le seuil : jamais de majorité, jamais de hold', () {
      final smoother = ChordSmoother();
      for (int i = 0; i < 3; i++) {
        final r = smoother.push(makeChord(chordName: 'C', confidence: 0.5));
        expect(r.kind, SmoothedChordKind.indeterminate);
      }
    });
  });
}
