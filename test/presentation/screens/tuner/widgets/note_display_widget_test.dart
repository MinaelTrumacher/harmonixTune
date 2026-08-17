import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:harmonix_tune/domain/entities/pitch_result.dart';
import 'package:harmonix_tune/domain/entities/tuning_configuration.dart';
import 'package:harmonix_tune/domain/enums/tuner_state.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_bloc.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_event.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_state.dart';
import 'package:harmonix_tune/presentation/screens/tuner/widgets/note_display_widget.dart';

class MockTunerBloc extends MockBloc<TunerEvent, TunerDisplayState>
    implements TunerBloc {}

void main() {
  late MockTunerBloc bloc;

  setUp(() {
    bloc = MockTunerBloc();
  });

  Widget wrap() => MaterialApp(
    home: Scaffold(
      body: BlocProvider<TunerBloc>.value(
        value: bloc,
        child: const NoteDisplayWidget(),
      ),
    ),
  );

  testWidgets('état initial : affiche "--" et "--- Hz"', (tester) async {
    when(() => bloc.state).thenReturn(const TunerInitial());

    await tester.pumpWidget(wrap());

    expect(find.text('--'), findsOneWidget);
    expect(find.text('--- Hz'), findsOneWidget);
  });

  testWidgets('TunerListening : affiche le nom de note, l\'octave et les Hz', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(
      const TunerListening(
        pitch: PitchResult(
          frequencyHz: 329.63,
          noteName: 'E',
          octave: 4,
          centsDeviation: 1.2,
          confidence: 0.95,
          state: TunerState.inTune,
        ),
        config: TuningConfiguration(),
        intelliTunerEnabled: false,
      ),
    );

    await tester.pumpWidget(wrap());

    expect(find.text('E'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('329.6 Hz'), findsOneWidget);
  });
}
