import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/domain/entities/tuning_profile.dart';
import 'package:harmonix_tune/domain/repositories/tuning_profile_repository.dart';
import 'package:harmonix_tune/presentation/app.dart';

// Fake en mémoire — le smoke test n'a pas besoin d'une vraie base Hive.
class _InMemoryTuningProfileRepository implements TuningProfileRepository {
  @override
  Stream<List<TuningProfile>> watchAll() => Stream.value(const []);

  @override
  Future<TuningProfile?> getById(String id) async => null;

  @override
  Future<void> save(TuningProfile profile) async {}

  @override
  Future<void> delete(String id) async {}
}

void main() {
  testWidgets('App smoke test — démarre sans crash', (
    WidgetTester tester,
  ) async {
    // Le runner CI utilise 800×600dp — trop petit pour notre layout portrait.
    // On impose les dimensions d'un smartphone réel (iPhone 15 : 393×852dp @ 3×).
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HarmonixTuneApp(
        tuningProfileRepository: _InMemoryTuningProfileRepository(),
      ),
    );
    await tester.pump();
    expect(find.byType(HarmonixTuneApp), findsOneWidget);
  });
}
