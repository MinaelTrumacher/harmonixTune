import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/data/datasources/audio_buffer_accumulator.dart';

void main() {
  const chunkBytes = 4096; // 2048 samples × 2 bytes

  AudioBufferAccumulator make() => AudioBufferAccumulator(chunkBytes);

  group('AudioBufferAccumulator — émission de chunks', () {
    test('chunk exact → émet immédiatement 1 buffer', () {
      final acc = make();
      final data = Uint8List(chunkBytes);
      final result = acc.feed(data).toList();
      expect(result, hasLength(1));
      expect(result.first.length, equals(chunkBytes));
    });

    test('chunk trop petit → ne retourne rien', () {
      final acc = make();
      final result = acc.feed(Uint8List(100)).toList();
      expect(result, isEmpty);
    });

    test('accumulation de petits chunks → émet quand le seuil est atteint', () {
      final acc = make();
      acc.feed(Uint8List(2000));   // < 4096 → rien
      acc.feed(Uint8List(2000));   // 4000 < 4096 → rien
      final third = acc.feed(Uint8List(200)).toList(); // 4200 ≥ 4096 → 1 buffer
      expect(third, hasLength(1));
      expect(third.first.length, equals(chunkBytes));
    });

    test('chunk double → émet 2 buffers', () {
      final acc = make();
      final result = acc.feed(Uint8List(chunkBytes * 2)).toList();
      expect(result, hasLength(2));
    });

    test('reste après émission est conservé pour le prochain appel', () {
      final acc = make();
      // Premier appel : 5000 bytes → 1 chunk de 4096, reste 904
      acc.feed(Uint8List(5000));
      // Deuxième appel : 904 + 3500 = 4404 → 1 chunk de 4096, reste 308
      final second = acc.feed(Uint8List(3500)).toList();
      expect(second, hasLength(1));
    });

    test('données du chunk sont correctes (valeurs préservées)', () {
      final acc = make();
      final data = Uint8List.fromList(List.generate(chunkBytes, (i) => i % 256));
      final result = acc.feed(data).toList();
      expect(result.first, equals(data));
    });

    test('données restantes sont annexées au chunk suivant, pas écrasées', () {
      final acc = make();
      // Envoyer 3000 bytes avec valeur 0xAA
      acc.feed(Uint8List.fromList(List.filled(3000, 0xAA)));
      // Compléter avec 1096 bytes valeur 0xBB → total 4096 → 1 chunk
      final result =
          acc.feed(Uint8List.fromList(List.filled(1096, 0xBB))).toList();
      expect(result, hasLength(1));
      // Les 3000 premiers bytes doivent être 0xAA
      expect(result.first.sublist(0, 3000), everyElement(0xAA));
      // Les 1096 suivants doivent être 0xBB
      expect(result.first.sublist(3000), everyElement(0xBB));
    });
  });

  group('AudioBufferAccumulator — clear', () {
    test('clear vide le buffer interne — pas d\'émission parasite ensuite', () {
      final acc = make();
      acc.feed(Uint8List(3000)); // 3000 en attente
      acc.clear();
      // Maintenant 200 bytes → pas encore un chunk complet
      final result = acc.feed(Uint8List(200)).toList();
      expect(result, isEmpty);
    });
  });

  group('AudioBufferAccumulator — taille de chunk configurable', () {
    test('chunk de 8192 bytes → se comporte correctement', () {
      final acc = AudioBufferAccumulator(8192);
      acc.feed(Uint8List(4000));
      final result = acc.feed(Uint8List(4192)).toList();
      expect(result, hasLength(1));
      expect(result.first.length, equals(8192));
    });
  });
}
