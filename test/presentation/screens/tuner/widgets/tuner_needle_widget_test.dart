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
import 'package:harmonix_tune/presentation/screens/tuner/widgets/tuner_needle_widget.dart';

class MockTunerBloc extends MockBloc<TunerEvent, TunerDisplayState>
    implements TunerBloc {}

TunerListening _listening(double cents, TunerState state) => TunerListening(
  pitch: PitchResult(
    frequencyHz: 110,
    noteName: 'A',
    octave: 2,
    centsDeviation: cents,
    confidence: 0.95,
    state: state,
  ),
  config: const TuningConfiguration(),
  intelliTunerEnabled: false,
);

void main() {
  late MockTunerBloc bloc;

  setUp(() {
    bloc = MockTunerBloc();
  });

  // Comme CentsBarWidget, le Ticker tourne indéfiniment : pas de
  // `pumpAndSettle()` ici, un nombre fixe de `pump(duration)` suffit.
  Widget wrap() => MaterialApp(
    home: Scaffold(
      body: BlocProvider<TunerBloc>.value(
        value: bloc,
        child: const SizedBox(
          width: 300,
          height: 190,
          child: TunerNeedleWidget(),
        ),
      ),
    ),
  );

  testWidgets('se construit sans exception sur l\'état initial', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(const TunerInitial());
    whenListen(bloc, const Stream<TunerDisplayState>.empty());

    await tester.pumpWidget(wrap());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('suit les changements d\'état émis par le BLoC sans exception', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(_listening(0, TunerState.silent));
    whenListen(
      bloc,
      Stream.fromIterable([
        _listening(-50, TunerState.tooLow),
        _listening(0, TunerState.inTune),
        _listening(50, TunerState.tooHigh),
        _listening(0, TunerState.silent),
      ]),
    );

    await tester.pumpWidget(wrap());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(tester.takeException(), isNull);
  });
}
