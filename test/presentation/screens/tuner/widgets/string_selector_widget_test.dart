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
import 'package:harmonix_tune/presentation/screens/tuner/widgets/string_selector_widget.dart';

class MockTunerBloc extends MockBloc<TunerEvent, TunerDisplayState>
    implements TunerBloc {}

const _pitch = PitchResult(
  frequencyHz: 110,
  noteName: 'A',
  octave: 2,
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
        child: const StringSelectorWidget(),
      ),
    ),
  );

  testWidgets(
    'mode AUTO (targetString null) : les 6 cordes en opacité réduite',
    (tester) async {
      when(() => bloc.state).thenReturn(
        const TunerListening(
          pitch: _pitch,
          config: TuningConfiguration(),
          intelliTunerEnabled: false,
        ),
      );

      await tester.pumpWidget(wrap());

      for (final note in ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']) {
        expect(find.text(note), findsOneWidget);
      }
      final opacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((w) => w.opacity)
          .toSet();
      expect(opacities, {0.4});
    },
  );

  testWidgets('corde sélectionnée : opacité pleine (1.0)', (tester) async {
    when(() => bloc.state).thenReturn(
      const TunerListening(
        pitch: _pitch,
        config: TuningConfiguration(targetString: 'D3'),
        intelliTunerEnabled: false,
      ),
    );

    await tester.pumpWidget(wrap());

    final opacities = tester
        .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .map((w) => w.opacity)
        .toSet();
    expect(opacities, {1.0});
  });

  testWidgets('tap sur une corde en mode AUTO envoie StringSelected(note)', (
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
    await tester.tap(find.text('D3'));

    verify(() => bloc.add(const StringSelected('D3'))).called(1);
  });

  testWidgets(
    'tap sur la corde déjà sélectionnée envoie StringSelected(null)',
    (tester) async {
      when(() => bloc.state).thenReturn(
        const TunerListening(
          pitch: _pitch,
          config: TuningConfiguration(targetString: 'D3'),
          intelliTunerEnabled: false,
        ),
      );

      await tester.pumpWidget(wrap());
      await tester.tap(find.text('D3'));

      verify(() => bloc.add(const StringSelected(null))).called(1);
    },
  );

  testWidgets(
    'reflète la config d\'un preset même avant toute détection de hauteur '
    '(TunerInitial) — sinon un preset appliqué avant le premier son capté '
    'restait invisible',
    (tester) async {
      when(() => bloc.state).thenReturn(
        const TunerInitial(
          config: TuningConfiguration(
            stringNotes: ['F2', 'A2', 'C3', 'G3', 'C3', 'E4'],
            presetId: 'p1',
          ),
        ),
      );

      await tester.pumpWidget(wrap());

      for (final note in ['F2', 'A2', 'C3', 'G3', 'C3', 'E4']) {
        expect(find.text(note), findsWidgets);
      }
      expect(find.text('E2'), findsNothing);
      expect(find.text('D3'), findsNothing);
      expect(find.text('B3'), findsNothing);
    },
  );
}
