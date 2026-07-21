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
import 'package:harmonix_tune/presentation/screens/tuner/widgets/cents_bar_widget.dart';

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

  // Le widget démarre un Ticker qui tourne indéfiniment (interpolation
  // continue) : `pumpAndSettle()` boucle sans fin sur ce widget, on utilise
  // donc `pump(duration)` avec un nombre fixe d'itérations.
  Widget wrap() => MaterialApp(
    home: Scaffold(
      body: BlocProvider<TunerBloc>.value(
        value: bloc,
        child: const SizedBox(width: 300, height: 60, child: CentsBarWidget()),
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
        _listening(-40, TunerState.tooLow),
        _listening(0, TunerState.inTune),
        _listening(40, TunerState.tooHigh),
      ]),
    );

    await tester.pumpWidget(wrap());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(tester.takeException(), isNull);
  });
}
