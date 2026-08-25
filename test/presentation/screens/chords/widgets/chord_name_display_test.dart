import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:harmonix_tune/domain/entities/chord_result.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_detector_bloc.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_event.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_smoother.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_state.dart';
import 'package:harmonix_tune/presentation/screens/chords/widgets/chord_name_display.dart';

class MockChordDetectorBloc extends MockBloc<ChordEvent, ChordDisplayState>
    implements ChordDetectorBloc {}

ChordResult _chord(String name, {double confidence = 0.9}) => ChordResult(
  chordName: name,
  chromaVector: const [1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0],
  confidence: confidence,
  activeNoteIndices: const {0, 4, 7},
);

void main() {
  late MockChordDetectorBloc bloc;

  setUp(() {
    bloc = MockChordDetectorBloc();
  });

  Widget wrap() => MaterialApp(
    home: Scaffold(
      body: BlocProvider<ChordDetectorBloc>.value(
        value: bloc,
        child: const ChordNameDisplay(),
      ),
    ),
  );

  testWidgets('état initial : affiche "--" et "En attente…"', (tester) async {
    when(() => bloc.state).thenReturn(const ChordInitial());

    await tester.pumpWidget(wrap());

    expect(find.text('--'), findsOneWidget);
    expect(find.text('En attente…'), findsOneWidget);
  });

  testWidgets('kind=silent : affiche "--" et "Jouez un accord"', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(
      ChordListening(
        smoothed: SmoothedChord(
          kind: SmoothedChordKind.silent,
          result: ChordResult.silent,
        ),
      ),
    );

    await tester.pumpWidget(wrap());

    expect(find.text('--'), findsOneWidget);
    expect(find.text('Jouez un accord'), findsOneWidget);
  });

  testWidgets('kind=indeterminate : affiche "?" et "Indéterminé"', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(
      ChordListening(
        smoothed: SmoothedChord(
          kind: SmoothedChordKind.indeterminate,
          result: _chord('C'),
        ),
      ),
    );

    await tester.pumpWidget(wrap());

    expect(find.text('?'), findsOneWidget);
    expect(find.text('Indéterminé'), findsOneWidget);
  });

  testWidgets('kind=detected : affiche le nom de l\'accord et la confiance', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(
      ChordListening(
        smoothed: SmoothedChord(
          kind: SmoothedChordKind.detected,
          result: _chord('Am', confidence: 0.82),
        ),
      ),
    );

    await tester.pumpWidget(wrap());

    expect(find.text('Am'), findsOneWidget);
    expect(find.text('82% de confiance'), findsOneWidget);
  });
}
