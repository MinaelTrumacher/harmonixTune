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
import 'package:harmonix_tune/presentation/screens/tuner/widgets/intelli_tuner_toggle.dart';

class MockTunerBloc extends MockBloc<TunerEvent, TunerDisplayState>
    implements TunerBloc {}

const _pitch = PitchResult(
  frequencyHz: 329.6,
  noteName: 'E',
  octave: 4,
  centsDeviation: 0,
  confidence: 0.95,
  state: TunerState.inTune,
);

void main() {
  late MockTunerBloc bloc;

  setUp(() {
    bloc = MockTunerBloc();
  });

  Widget wrap() => MaterialApp(
    home: Scaffold(
      body: BlocProvider<TunerBloc>.value(
        value: bloc,
        child: const IntelliTunerToggle(),
      ),
    ),
  );

  testWidgets('état initial (hors écoute) : switch désactivé', (tester) async {
    when(() => bloc.state).thenReturn(const TunerInitial());

    await tester.pumpWidget(wrap());

    final switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.value, isFalse);
  });

  testWidgets('TunerListening, intelliTunerEnabled=false : switch désactivé', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(
      const TunerListening(
        pitch: _pitch,
        config: TuningConfiguration(),
        intelliTunerEnabled: false,
      ),
    );

    await tester.pumpWidget(wrap());

    final switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.value, isFalse);
  });

  testWidgets('TunerListening, intelliTunerEnabled=true : switch activé', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(
      const TunerListening(
        pitch: _pitch,
        config: TuningConfiguration(),
        intelliTunerEnabled: true,
      ),
    );

    await tester.pumpWidget(wrap());

    final switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.value, isTrue);
  });

  testWidgets('activer le switch envoie IntelliTunerToggled(enabled: true)', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(
      const TunerListening(
        pitch: _pitch,
        config: TuningConfiguration(),
        intelliTunerEnabled: false,
      ),
    );

    await tester.pumpWidget(wrap());
    await tester.tap(find.byType(Switch));

    verify(() => bloc.add(const IntelliTunerToggled(enabled: true))).called(1);
  });
}
