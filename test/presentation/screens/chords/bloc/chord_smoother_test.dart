import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/domain/entities/chord_result.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_smoother.dart';

ChordResult makeChord({
  required String chordName,
  String? familyName,
  double confidence = 0.9,
}) => ChordResult(
  chordName: chordName,
  familyName: familyName ?? chordName,
  chromaVector: const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  confidence: confidence,
  activeNoteIndices: const {},
);

// Réglages par défaut de production (fenêtre=6, attaque=2, clôture=3,
// marge=0.08, confiance min=0.65) sauf timeout, raccourci pour des tests
// pratiques à écrire.
ChordSmoother makeSmoother({int? silenceTimeoutFrames}) =>
    ChordSmoother(silenceTimeoutFrames: silenceTimeoutFrames ?? 108);

/// Pousse [count] frames d'attaque (ignorées par le vote) sur [smoother].
void _skipAttack(ChordSmoother smoother, {int count = 2}) {
  for (int i = 0; i < count; i++) {
    smoother.push(makeChord(chordName: 'X', familyName: 'X'));
  }
}

void main() {
  group('ChordSmoother — état initial / silence', () {
    test('silence avant tout onset → état silent', () {
      final result = makeSmoother().push(ChordResult.silent);
      expect(result.kind, SmoothedChordKind.silent);
      expect(result.result.chordName, '--');
    });
  });

  group('ChordSmoother — attaque ignorée (attackFramesToSkip=2)', () {
    test('les 2 premières frames d\'un onset ne votent pas', () {
      final smoother = makeSmoother();
      final r1 = smoother.push(makeChord(chordName: 'F'));
      expect(r1.kind, SmoothedChordKind.indeterminate);
      final r2 = smoother.push(makeChord(chordName: 'G7', familyName: 'G'));
      expect(r2.kind, SmoothedChordKind.indeterminate);
    });

    test('le vote démarre à la 3e frame de l\'événement', () {
      final smoother = makeSmoother();
      _skipAttack(smoother);
      final r3 = smoother.push(makeChord(chordName: 'C', confidence: 0.9));
      expect(r3.kind, SmoothedChordKind.detected);
      expect(r3.result.chordName, 'C');
    });
  });

  group('ChordSmoother — vote pondéré par confiance cumulée', () {
    test('confiance affichée = moyenne des frames soutenant ce nom', () {
      final smoother = makeSmoother();
      _skipAttack(smoother);
      smoother.push(makeChord(chordName: 'C', confidence: 0.9));
      smoother.push(makeChord(chordName: 'C', confidence: 0.8));
      smoother.push(makeChord(chordName: 'C', confidence: 0.7));
      final r = smoother.push(makeChord(chordName: 'C', confidence: 0.75));

      expect(r.kind, SmoothedChordKind.detected);
      expect(r.result.chordName, 'C');
      // (0.9 + 0.8 + 0.7 + 0.75) / 4
      expect(r.result.confidence, closeTo(0.7875, 1e-9));
    });

    test('les frames sous chordMinConfidence n\'entrent pas dans le vote', () {
      final smoother = makeSmoother();
      _skipAttack(smoother);
      final r = smoother.push(makeChord(chordName: 'C', confidence: 0.5));
      expect(r.kind, SmoothedChordKind.indeterminate);
    });

    test('une famille diluée sur une seule frame perd face à une famille '
        'mieux représentée dans la fenêtre', () {
      final smoother = makeSmoother();
      _skipAttack(smoother);
      // 1 frame "G" contre 3 frames "C" — "C" doit dominer la moyenne
      // sur la fenêtre (dénominateur fixe = 6), même si "G" a une
      // confiance ponctuelle plus haute.
      smoother.push(makeChord(chordName: 'G', confidence: 0.99));
      smoother.push(makeChord(chordName: 'C', confidence: 0.8));
      smoother.push(makeChord(chordName: 'C', confidence: 0.8));
      final r = smoother.push(makeChord(chordName: 'C', confidence: 0.8));

      expect(r.result.chordName, 'C');
    });
  });

  group('ChordSmoother — persistance requise pour une variante à 7e', () {
    test('"F7" l\'emporte sur "F" quand il est soutenu par au moins la '
        'moitié de la fenêtre ET dépasse la marge en moyenne', () {
      final smoother = makeSmoother();
      _skipAttack(smoother);
      // Fenêtre pleine (6) : 4×F7 (0.9) + 2×F (0.9).
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.9),
      );
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.9),
      );
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.9),
      );
      smoother.push(makeChord(chordName: 'F', confidence: 0.9));
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.9),
      );
      final r = smoother.push(makeChord(chordName: 'F', confidence: 0.9));

      expect(r.result.chordName, 'F7');
      // Moyenne des 4 frames F7 : (0.9*4)/4
      expect(r.result.confidence, closeTo(0.9, 1e-9));
    });

    test('un pic isolé de "F7" (1 seule frame de soutien) ne suffit pas '
        'même à confiance très élevée — reste sur la triade "F"', () {
      final smoother = makeSmoother();
      _skipAttack(smoother);
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.99),
      );
      smoother.push(makeChord(chordName: 'F', confidence: 0.9));
      smoother.push(makeChord(chordName: 'F', confidence: 0.9));
      smoother.push(makeChord(chordName: 'F', confidence: 0.9));
      smoother.push(makeChord(chordName: 'F', confidence: 0.9));
      final r = smoother.push(makeChord(chordName: 'F', confidence: 0.9));

      expect(r.result.chordName, 'F');
    });

    test('soutien suffisant (3/6) mais écart moyen sous la marge → reste '
        'sur la triade', () {
      final smoother = makeSmoother(); // complexityMargin = 0.08
      _skipAttack(smoother);
      // 3×F7 (0.9) + 3×F (0.9) : moyennes égales → écart nul.
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.9),
      );
      smoother.push(makeChord(chordName: 'F', confidence: 0.9));
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.9),
      );
      smoother.push(makeChord(chordName: 'F', confidence: 0.9));
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.9),
      );
      final r = smoother.push(makeChord(chordName: 'F', confidence: 0.9));

      expect(r.result.chordName, 'F');
    });

    test('cas limite : la triade de base n\'apparaît jamais directement '
        '(seule une 7e isolée, bloquée par le garde-fou) — pas d\'exception, '
        'confiance repliée sur la moyenne de la famille', () {
      final smoother = makeSmoother();
      _skipAttack(smoother);
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.95),
      );
      // Les 5 frames suivantes sont sous chordMinConfidence → ignorées du
      // vote, mais occupent quand même la fenêtre glissante.
      for (int i = 0; i < 4; i++) {
        smoother.push(
          makeChord(chordName: 'Z', familyName: 'Z', confidence: 0.5),
        );
      }
      final r = smoother.push(
        makeChord(chordName: 'Z', familyName: 'Z', confidence: 0.5),
      );

      expect(r.result.chordName, 'F');
      expect(r.result.confidence, closeTo(0.95, 1e-9));
    });
  });

  group('ChordSmoother — clôture d\'événement (creux vs vraie fin)', () {
    test('un creux de 1 à 2 frames silencieuses ne réinitialise pas la '
        'fenêtre de vote', () {
      final smoother = makeSmoother();
      _skipAttack(smoother);
      smoother.push(makeChord(chordName: 'C', confidence: 0.9));
      smoother.push(makeChord(chordName: 'C', confidence: 0.9));

      smoother.push(ChordResult.silent); // creux 1/3
      smoother.push(ChordResult.silent); // creux 2/3

      // Reprise avant clôture : le vote continue sans repartir de zéro.
      final r = smoother.push(makeChord(chordName: 'C', confidence: 0.9));
      expect(r.kind, SmoothedChordKind.detected);
      expect(r.result.chordName, 'C');
    });

    test('l\'accord résolu reste affiché pendant et après la clôture '
        '(ne disparaît pas)', () {
      final smoother = makeSmoother();
      _skipAttack(smoother);
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.9),
      );
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.9),
      );
      smoother.push(
        makeChord(chordName: 'F7', familyName: 'F', confidence: 0.9),
      );

      final s1 = smoother.push(ChordResult.silent);
      final s2 = smoother.push(ChordResult.silent);
      final s3 = smoother.push(ChordResult.silent); // clôture (3/3)
      final s4 = smoother.push(ChordResult.silent); // silence prolongé

      for (final s in [s1, s2, s3, s4]) {
        expect(s.kind, SmoothedChordKind.detected);
      }
    });
  });

  group('ChordSmoother — nouvel onset après clôture', () {
    test('un nouvel onset repart d\'une fenêtre vide (n\'hérite pas de '
        'l\'ancienne famille) et garde l\'ancien accord affiché pendant '
        'sa propre attaque', () {
      final smoother = makeSmoother();
      _skipAttack(smoother);
      smoother.push(makeChord(chordName: 'C', confidence: 0.9));
      smoother.push(makeChord(chordName: 'C', confidence: 0.9));

      smoother.push(ChordResult.silent);
      smoother.push(ChordResult.silent);
      smoother.push(ChordResult.silent); // événement "C" clos

      final a1 = smoother.push(makeChord(chordName: 'G', confidence: 0.9));
      expect(a1.result.chordName, 'C'); // attaque du nouvel onset : tenu

      final a2 = smoother.push(makeChord(chordName: 'G', confidence: 0.9));
      expect(a2.result.chordName, 'C');

      final a3 = smoother.push(makeChord(chordName: 'G', confidence: 0.9));
      expect(a3.kind, SmoothedChordKind.detected);
      expect(a3.result.chordName, 'G');
    });
  });

  group('ChordSmoother — timeout de silence prolongé', () {
    test('après silenceTimeoutFrames de silence total, réinitialise sur '
        'l\'état silencieux', () {
      final smoother = makeSmoother(silenceTimeoutFrames: 5);
      _skipAttack(smoother);
      smoother.push(makeChord(chordName: 'C', confidence: 0.9));

      for (int i = 0; i < 4; i++) {
        final r = smoother.push(ChordResult.silent);
        expect(r.kind, SmoothedChordKind.detected, reason: 'frame silence #$i');
      }

      final timedOut = smoother.push(ChordResult.silent);
      expect(timedOut.kind, SmoothedChordKind.silent);
    });
  });
}
