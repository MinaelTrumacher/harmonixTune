import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/presentation/app.dart';

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

    await tester.pumpWidget(const HarmonixTuneApp());
    await tester.pump();
    expect(find.byType(HarmonixTuneApp), findsOneWidget);
  });
}
