import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:harmonix_tune/domain/entities/tuning_profile.dart';
import 'package:harmonix_tune/domain/enums/instrument_type.dart';
import 'package:harmonix_tune/domain/repositories/tuning_profile_repository.dart';
import 'package:harmonix_tune/presentation/screens/presets/profile_editor_screen.dart';

class MockTuningProfileRepository extends Mock
    implements TuningProfileRepository {}

class FakeTuningProfile extends Fake implements TuningProfile {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeTuningProfile());
  });

  late MockTuningProfileRepository mockRepo;

  setUp(() {
    mockRepo = MockTuningProfileRepository();
    when(() => mockRepo.watchAll()).thenAnswer((_) => Stream.value(const []));
    when(() => mockRepo.save(any())).thenAnswer((_) async {});
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  // Le formulaire dépasse la hauteur par défaut du banc de test (800x600) :
  // sans ceci, "Ajouter une corde" / "Enregistrer le profil" ne sont jamais
  // montés dans l'arbre (SliverList ne construit que les enfants visibles).
  Future<void> pumpTall(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  group('ProfileEditorScreen — rendu initial', () {
    testWidgets('affiche 6 champs cordes (gabarit guitare par défaut)', (
      tester,
    ) async {
      await pumpTall(tester, wrap(ProfileEditorScreen(repository: mockRepo)));

      for (var i = 1; i <= 6; i++) {
        expect(find.text('Corde $i'), findsOneWidget);
      }
      expect(find.text('Corde 7'), findsNothing);
    });

    testWidgets('affiche le bouton "Ajouter une corde" et "Enregistrer"', (
      tester,
    ) async {
      await pumpTall(tester, wrap(ProfileEditorScreen(repository: mockRepo)));

      expect(find.text('Ajouter une corde'), findsOneWidget);
      expect(find.text('Enregistrer le profil'), findsOneWidget);
    });

    testWidgets('affiche un bouton de suppression par corde (6 > min 3)', (
      tester,
    ) async {
      await pumpTall(tester, wrap(ProfileEditorScreen(repository: mockRepo)));

      expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(6));
    });
  });

  group('ProfileEditorScreen — changement d\'instrument', () {
    testWidgets('Basse réinitialise à 4 cordes par défaut', (tester) async {
      await pumpTall(tester, wrap(ProfileEditorScreen(repository: mockRepo)));

      await tester.tap(find.byType(DropdownButtonFormField<InstrumentType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Basse').last);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(4));
      expect(find.text('Corde 5'), findsNothing);
    });
  });

  group('ProfileEditorScreen — ajout / suppression de cordes', () {
    testWidgets('"Ajouter une corde" fait passer de 6 à 7 champs', (
      tester,
    ) async {
      await pumpTall(tester, wrap(ProfileEditorScreen(repository: mockRepo)));

      await tester.tap(find.text('Ajouter une corde'));
      await tester.pumpAndSettle();

      expect(find.text('Corde 7'), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(7));
    });

    testWidgets('le bouton "Ajouter une corde" disparaît à la limite de 8', (
      tester,
    ) async {
      await pumpTall(tester, wrap(ProfileEditorScreen(repository: mockRepo)));

      // 6 cordes par défaut → 2 ajouts pour atteindre le max (8).
      await tester.tap(find.text('Ajouter une corde'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter une corde'));
      await tester.pumpAndSettle();

      expect(find.text('Corde 8'), findsOneWidget);
      expect(find.text('Ajouter une corde'), findsNothing);
    });

    testWidgets('suppression d\'une corde fait passer de 6 à 5 champs', (
      tester,
    ) async {
      await pumpTall(tester, wrap(ProfileEditorScreen(repository: mockRepo)));

      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('Corde 6'), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(5));
    });

    testWidgets(
      'le bouton de suppression disparaît à la limite basse de 3 cordes',
      (tester) async {
        await pumpTall(tester, wrap(ProfileEditorScreen(repository: mockRepo)));

        // 6 cordes par défaut → 3 suppressions pour atteindre le min (3).
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
          await tester.pumpAndSettle();
        }

        expect(find.text('Corde 3'), findsOneWidget);
        expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
      },
    );
  });

  group('ProfileEditorScreen — validation et sauvegarde', () {
    testWidgets('nom vide → message d\'erreur affiché, save() jamais appelé', (
      tester,
    ) async {
      await pumpTall(tester, wrap(ProfileEditorScreen(repository: mockRepo)));

      await tester.tap(find.text('Enregistrer le profil'));
      await tester.pumpAndSettle();

      expect(
        find.text('Le nom du profil doit contenir entre 3 et 50 caractères.'),
        findsOneWidget,
      );
      verifyNever(() => mockRepo.save(any()));
    });

    testWidgets('nom valide → save() appelé et l\'écran se ferme (pop)', (
      tester,
    ) async {
      await pumpTall(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProfileEditorScreen(repository: mockRepo),
                  ),
                ),
                child: const Text('open-editor'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-editor'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byWidgetPredicate((w) => w is TextFormField).first,
        'Mon Profil Test',
      );
      await tester.tap(find.text('Enregistrer le profil'));
      await tester.pumpAndSettle();

      verify(() => mockRepo.save(any())).called(1);
      expect(find.text('open-editor'), findsOneWidget);
    });
  });
}
