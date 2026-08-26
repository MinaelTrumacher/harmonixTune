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

// Réglages par défaut de production : 2 frames d'attaque ignorées, 3 frames
// silencieuses pour clore un événement.
ChordSmoother makeSmoother({int? silenceTimeoutFrames}) => ChordSmoother(
  silenceTimeoutFrames: silenceTimeoutFrames ?? 108,
);

void main() {
  group('ChordSmoother — état initial / silence', () {
    test('silence avant tout onset → état silent', () {
      final smoother = makeSmoother();
      final result = smoother.push(ChordResult.silent);
      expect(result.kind, SmoothedChordKind.silent);
      expect(result.result.chordName, '--');
    });
  });

  group('ChordSmoother — attaque ignorée (attackFramesToSkip=2)', () {
    test('les 2 premières frames d\'un onset ne votent pas', () {
      final smoother = makeSmoother();
      // Rien à tenir avant la 1re frame jouée : indéterminé pendant
      // l'attaque, faute de mieux à montrer.
      final r1 = smoother.push(makeChord(chordName: 'F', confidence: 0.95));
      expect(r1.kind, SmoothedChordKind.indeterminate);

      final r2 = smoother.push(makeChord(chordName: 'G7', confidence: 0.7));
      expect(r2.kind, SmoothedChordKind.indeterminate);
    });

    test('le vote démarre à la 3e frame de l\'événement', () {
      final smoother = makeSmoother();
      smoother.push(makeChord(chordName: 'F', confidence: 0.95)); // attaque
      smoother.push(makeChord(chordName: 'G7', confidence: 0.7)); // attaque
      final r3 = smoother.push(makeChord(chordName: 'Fmaj7', confidence: 0.9));

      expect(r3.kind, SmoothedChordKind.detected);
      expect(r3.result.chordName, 'Fmaj7');
      expect(r3.result.confidence, closeTo(0.9, 1e-9));
    });
  });

  group('ChordSmoother — vote majoritaire cumulé sur l\'événement', () {
    test('le nom majoritaire l\'emporte, confiance = moyenne de ses votes', () {
      final smoother = makeSmoother();
      smoother.push(makeChord(chordName: 'X')); // attaque, ignorée
      smoother.push(makeChord(chordName: 'X')); // attaque, ignorée

      smoother.push(makeChord(chordName: 'Fmaj7', confidence: 0.80));
      smoother.push(makeChord(chordName: 'G7', confidence: 0.70)); // bruit
      final r = smoother.push(makeChord(chordName: 'Fmaj7', confidence: 0.90));

      expect(r.kind, SmoothedChordKind.detected);
      expect(r.result.chordName, 'Fmaj7');
      // Moyenne des 2 votes "Fmaj7" (0.80 et 0.90) — "G7" n'a qu'un vote.
      expect(r.result.confidence, closeTo(0.85, 1e-9));
    });

    test('les votes sous chordMinConfidence ne comptent pas', () {
      final smoother = ChordSmoother(minConfidence: 0.65, silenceTimeoutFrames: 108);
      smoother.push(makeChord(chordName: 'X'));
      smoother.push(makeChord(chordName: 'X'));

      final r = smoother.push(makeChord(chordName: 'C', confidence: 0.5));
      // Aucun vote valide, rien à tenir → indéterminé.
      expect(r.kind, SmoothedChordKind.indeterminate);
    });
  });

  group('ChordSmoother — clôture d\'événement (eventCloseSilentFrames=3)', () {
    test('un creux de 1 à 2 frames silencieuses ne clôt pas l\'événement '
        '(pas de reset du vote)', () {
      final smoother = makeSmoother();
      smoother.push(makeChord(chordName: 'X')); // attaque
      smoother.push(makeChord(chordName: 'X')); // attaque
      smoother.push(makeChord(chordName: 'C', confidence: 0.9)); // vote 1

      smoother.push(ChordResult.silent); // creux 1/3
      smoother.push(ChordResult.silent); // creux 2/3

      // Reprise avant clôture : pas de nouvel onset, le vote continue
      // immédiatement (pas de 2 frames d'attaque à ré-ignorer).
      final r = smoother.push(makeChord(chordName: 'C', confidence: 0.9));
      expect(r.kind, SmoothedChordKind.detected);
      expect(r.result.chordName, 'C');
    });

    test('l\'accord résolu reste affiché pendant et après la clôture '
        '(ne disparaît pas)', () {
      final smoother = makeSmoother();
      smoother.push(makeChord(chordName: 'X'));
      smoother.push(makeChord(chordName: 'X'));
      smoother.push(makeChord(chordName: 'Fmaj7', confidence: 0.9));

      final s1 = smoother.push(ChordResult.silent);
      final s2 = smoother.push(ChordResult.silent);
      final s3 = smoother.push(ChordResult.silent); // clôture (3/3)
      final s4 = smoother.push(ChordResult.silent); // silence prolongé

      for (final s in [s1, s2, s3, s4]) {
        expect(s.kind, SmoothedChordKind.detected);
        expect(s.result.chordName, 'Fmaj7');
      }
    });
  });

  group('ChordSmoother — nouvel onset après clôture', () {
    test('un nouvel onset garde l\'ancien accord affiché pendant sa propre '
        'attaque, puis le remplace une fois voté', () {
      final smoother = makeSmoother();
      smoother.push(makeChord(chordName: 'X'));
      smoother.push(makeChord(chordName: 'X'));
      smoother.push(makeChord(chordName: 'C', confidence: 0.9));

      smoother.push(ChordResult.silent);
      smoother.push(ChordResult.silent);
      smoother.push(ChordResult.silent); // événement "C" clos

      // Nouvel onset : attaque du 2e strum, "C" doit rester affiché.
      final a1 = smoother.push(makeChord(chordName: 'G', confidence: 0.9));
      expect(a1.kind, SmoothedChordKind.detected);
      expect(a1.result.chordName, 'C');

      final a2 = smoother.push(makeChord(chordName: 'G', confidence: 0.9));
      expect(a2.result.chordName, 'C'); // toujours l'attaque, "C" tenu

      // 3e frame du nouvel événement : le vote démarre, "G" remplace "C".
      final a3 = smoother.push(makeChord(chordName: 'G', confidence: 0.9));
      expect(a3.kind, SmoothedChordKind.detected);
      expect(a3.result.chordName, 'G');
    });
  });

  group('ChordSmoother — timeout de silence prolongé', () {
    test('après silenceTimeoutFrames de silence total, réinitialise sur '
        'l\'état silencieux', () {
      final smoother = makeSmoother(silenceTimeoutFrames: 5);
      smoother.push(makeChord(chordName: 'X'));
      smoother.push(makeChord(chordName: 'X'));
      smoother.push(makeChord(chordName: 'C', confidence: 0.9));

      // 4 frames de silence : sous le timeout, "C" reste tenu.
      for (int i = 0; i < 4; i++) {
        final r = smoother.push(ChordResult.silent);
        expect(r.kind, SmoothedChordKind.detected, reason: 'frame silence #$i');
      }

      // 5e frame : timeout atteint → bascule sur silencieux.
      final timedOut = smoother.push(ChordResult.silent);
      expect(timedOut.kind, SmoothedChordKind.silent);
    });

    test('un nouvel onset après timeout redémarre comme un tout premier '
        'événement (attaque ignorée, rien à tenir)', () {
      final smoother = makeSmoother(silenceTimeoutFrames: 5);
      smoother.push(makeChord(chordName: 'X'));
      smoother.push(makeChord(chordName: 'X'));
      smoother.push(makeChord(chordName: 'C', confidence: 0.9));
      for (int i = 0; i < 5; i++) {
        smoother.push(ChordResult.silent);
      }

      final r = smoother.push(makeChord(chordName: 'G', confidence: 0.9));
      expect(r.kind, SmoothedChordKind.indeterminate);
    });
  });
}
