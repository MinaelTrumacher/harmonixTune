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
import 'package:harmonix_tune/presentation/screens/chords/widgets/chroma_bar_widget.dart';

class MockChordDetectorBloc extends MockBloc<ChordEvent, ChordDisplayState>
    implements ChordDetectorBloc {}

void main() {
  late MockChordDetectorBloc bloc;

  setUp(() {
    bloc = MockChordDetectorBloc();
  });

  Widget wrapWithBloc() => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 300,
        height: 120,
        child: BlocProvider<ChordDetectorBloc>.value(
          value: bloc,
          child: const ChromaBarWidget(),
        ),
      ),
    ),
  );

  testWidgets('état initial : se construit sans exception', (tester) async {
    when(() => bloc.state).thenReturn(const ChordInitial());
    whenListen(bloc, const Stream<ChordDisplayState>.empty());

    await tester.pumpWidget(wrapWithBloc());

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
    // 12 labels de degrés chromatiques (C, C#, D, ...).
    expect(find.text('C'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('accord Do majeur détecté : se construit sans exception', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(
      ChordListening(
        smoothed: SmoothedChord(
          kind: SmoothedChordKind.detected,
          result: const ChordResult(
            chordName: 'C',
            chromaVector: [1, 0, 0, 0, 0.8, 0, 0, 0.6, 0, 0, 0, 0],
            confidence: 0.95,
            activeNoteIndices: {0, 4, 7},
          ),
        ),
      ),
    );
    whenListen(bloc, const Stream<ChordDisplayState>.empty());

    await tester.pumpWidget(wrapWithBloc());

    expect(tester.takeException(), isNull);
  });

  testWidgets('suit les changements d\'état émis par le BLoC sans exception', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(const ChordInitial());
    whenListen(
      bloc,
      Stream.fromIterable([
        ChordListening(
          smoothed: SmoothedChord(
            kind: SmoothedChordKind.silent,
            result: ChordResult.silent,
          ),
        ),
        ChordListening(
          smoothed: SmoothedChord(
            kind: SmoothedChordKind.detected,
            result: const ChordResult(
              chordName: 'G',
              chromaVector: [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0.7],
              confidence: 0.9,
              activeNoteIndices: {7, 11, 2},
            ),
          ),
        ),
      ]),
    );

    await tester.pumpWidget(wrapWithBloc());
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
