import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:harmonix_tune/domain/entities/pitch_result.dart';
import 'package:harmonix_tune/domain/entities/tuning_configuration.dart';
import 'package:harmonix_tune/domain/entities/tuning_profile.dart';
import 'package:harmonix_tune/domain/enums/instrument_type.dart';
import 'package:harmonix_tune/domain/enums/tuner_state.dart';
import 'package:harmonix_tune/domain/repositories/tuning_profile_repository.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_bloc.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_event.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_state.dart';
import 'package:harmonix_tune/presentation/screens/tuner/widgets/tuning_preset_selector.dart';

class MockTunerBloc extends MockBloc<TunerEvent, TunerDisplayState>
    implements TunerBloc {}

class MockTuningProfileRepository extends Mock
    implements TuningProfileRepository {}

const _customProfile = TuningProfile(
  id: 'p1',
  name: 'Drop D perso',
  instrumentType: InstrumentType.guitar,
  stringNotes: ['D2', 'A2', 'D3', 'G3', 'B3', 'E4'],
);

void main() {
  late MockTunerBloc bloc;
  late MockTuningProfileRepository repo;

  setUp(() {
    bloc = MockTunerBloc();
    repo = MockTuningProfileRepository();
    when(() => repo.watchAll()).thenAnswer((_) => Stream.value(const []));
  });

  Widget wrap() => MaterialApp(
    home: Scaffold(
      body: BlocProvider<TunerBloc>.value(
        value: bloc,
        child: TuningPresetSelector(repository: repo),
      ),
    ),
  );

  testWidgets('affiche "Standard" quand aucun preset n\'est actif', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(const TunerInitial());

    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Standard'), findsOneWidget);
  });

  testWidgets('affiche le nom du profil actif', (tester) async {
    when(() => repo.watchAll()).thenAnswer(
      (_) => Stream.value(const [_customProfile]),
    );
    when(() => bloc.state).thenReturn(
      const TunerListening(
        pitch: PitchResult(
        frequencyHz: 110,
        noteName: 'A',
        octave: 2,
        centsDeviation: 0,
        confidence: 0.9,
        state: TunerState.inTune,
      ),
        config: TuningConfiguration(presetId: 'p1'),
        intelliTunerEnabled: false,
      ),
    );

    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Drop D perso'), findsOneWidget);
  });

  testWidgets(
    'tap ouvre le sélecteur listant "Standard" + les profils sauvegardés',
    (tester) async {
      when(() => repo.watchAll()).thenAnswer(
        (_) => Stream.value(const [_customProfile]),
      );
      when(() => bloc.state).thenReturn(const TunerInitial());

      await tester.pumpWidget(wrap());
      await tester.pump();
      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();

      // "Standard" apparaît 2 fois : le chip fermé + l'entrée du sélecteur.
      expect(find.text('Standard'), findsNWidgets(2));
      expect(find.text('Drop D perso'), findsOneWidget);
    },
  );

  testWidgets(
    'sélectionner un profil déclenche ConfigChanged avec ses cordes',
    (tester) async {
      when(() => repo.watchAll()).thenAnswer(
        (_) => Stream.value(const [_customProfile]),
      );
      when(() => bloc.state).thenReturn(const TunerInitial());

      await tester.pumpWidget(wrap());
      await tester.pump();
      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drop D perso'));
      await tester.pumpAndSettle();

      verify(
        () => bloc.add(
          const ConfigChanged(
            TuningConfiguration(
              stringNotes: ['D2', 'A2', 'D3', 'G3', 'B3', 'E4'],
              instrumentType: InstrumentType.guitar,
              presetId: 'p1',
            ),
          ),
        ),
      ).called(1);
    },
  );

  testWidgets(
    'revenir sur "Standard" déclenche ConfigChanged avec l\'accordage par défaut',
    (tester) async {
      when(() => repo.watchAll()).thenAnswer(
        (_) => Stream.value(const [_customProfile]),
      );
      when(() => bloc.state).thenReturn(
        const TunerListening(
          pitch: PitchResult(
        frequencyHz: 110,
        noteName: 'A',
        octave: 2,
        centsDeviation: 0,
        confidence: 0.9,
        state: TunerState.inTune,
      ),
          config: TuningConfiguration(
            stringNotes: ['D2', 'A2', 'D3', 'G3', 'B3', 'E4'],
            presetId: 'p1',
          ),
          intelliTunerEnabled: false,
        ),
      );

      await tester.pumpWidget(wrap());
      await tester.pump();
      await tester.tap(find.text('Drop D perso'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();

      verify(
        () => bloc.add(const ConfigChanged(TuningConfiguration())),
      ).called(1);
    },
  );
}
