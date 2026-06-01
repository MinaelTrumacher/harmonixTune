import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/presentation/app.dart';

void main() {
  testWidgets('App smoke test — démarre sans crash', (WidgetTester tester) async {
    await tester.pumpWidget(const HarmonixTuneApp());
    await tester.pump();
    expect(find.byType(HarmonixTuneApp), findsOneWidget);
  });
}
