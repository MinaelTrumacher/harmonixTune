import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/domain/exceptions/audio_permission_exception.dart';

void main() {
  group('AudioPermissionException', () {
    test('isPermanent est false par défaut', () {
      expect(const AudioPermissionException().isPermanent, isFalse);
    });

    test('isPermanent peut être true', () {
      expect(const AudioPermissionException(isPermanent: true).isPermanent, isTrue);
    });

    test('toString — refus temporaire', () {
      final msg = const AudioPermissionException().toString();
      expect(msg, contains('refus'));
    });

    test('toString — refus permanent mentionne définitif', () {
      final msg = const AudioPermissionException(isPermanent: true).toString();
      expect(msg, contains('définitivement'));
    });

    test('est une Exception', () {
      expect(const AudioPermissionException(), isA<Exception>());
    });
  });
}
