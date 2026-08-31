import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record/record.dart';

import 'package:harmonix_tune/core/constants/audio_constants.dart';
import 'package:harmonix_tune/data/datasources/record_microphone_data_source.dart';
import 'package:harmonix_tune/domain/exceptions/audio_permission_exception.dart';

class MockAudioRecorder extends Mock implements AudioRecorder {}

class MockPermissionHandlerPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements PermissionHandlerPlatform {}

void main() {
  late MockAudioRecorder mockRecorder;
  late MockPermissionHandlerPlatform mockPermissionPlatform;
  late RecordMicrophoneDataSource dataSource;

  setUpAll(() {
    registerFallbackValue(const RecordConfig(encoder: AudioEncoder.pcm16bits));
    registerFallbackValue(<Permission>[]);
  });

  setUp(() {
    mockRecorder = MockAudioRecorder();
    mockPermissionPlatform = MockPermissionHandlerPlatform();
    PermissionHandlerPlatform.instance = mockPermissionPlatform;
    dataSource = RecordMicrophoneDataSource(recorder: mockRecorder);
  });

  group('initialize', () {
    test(
      'lance AudioPermissionException(isPermanent: true) si déjà refusée définitivement',
      () async {
        when(
          () => mockPermissionPlatform.checkPermissionStatus(
            Permission.microphone,
          ),
        ).thenAnswer((_) async => PermissionStatus.permanentlyDenied);

        expect(
          () => dataSource.initialize(),
          throwsA(
            isA<AudioPermissionException>().having(
              (e) => e.isPermanent,
              'isPermanent',
              true,
            ),
          ),
        );
      },
    );

    test(
      'lance AudioPermissionException(isPermanent: false) si refusée à la demande',
      () async {
        when(
          () => mockPermissionPlatform.checkPermissionStatus(
            Permission.microphone,
          ),
        ).thenAnswer((_) async => PermissionStatus.denied);
        when(() => mockPermissionPlatform.requestPermissions(any())).thenAnswer(
          (_) async => {Permission.microphone: PermissionStatus.denied},
        );

        expect(
          () => dataSource.initialize(),
          throwsA(
            isA<AudioPermissionException>().having(
              (e) => e.isPermanent,
              'isPermanent',
              false,
            ),
          ),
        );
      },
    );

    test(
      'lance AudioPermissionException(isPermanent: true) si refusée définitivement à la demande',
      () async {
        when(
          () => mockPermissionPlatform.checkPermissionStatus(
            Permission.microphone,
          ),
        ).thenAnswer((_) async => PermissionStatus.denied);
        when(() => mockPermissionPlatform.requestPermissions(any())).thenAnswer(
          (_) async => {
            Permission.microphone: PermissionStatus.permanentlyDenied,
          },
        );

        expect(
          () => dataSource.initialize(),
          throwsA(
            isA<AudioPermissionException>().having(
              (e) => e.isPermanent,
              'isPermanent',
              true,
            ),
          ),
        );
      },
    );

    test('se termine normalement si la permission est accordée', () async {
      when(
        () =>
            mockPermissionPlatform.checkPermissionStatus(Permission.microphone),
      ).thenAnswer((_) async => PermissionStatus.denied);
      when(() => mockPermissionPlatform.requestPermissions(any())).thenAnswer(
        (_) async => {Permission.microphone: PermissionStatus.granted},
      );

      await expectLater(dataSource.initialize(), completes);
    });
  });

  group('stream', () {
    test(
      'démarre startStream avec la config PCM 16-bit mono attendue et relaie les buffers via l\'accumulateur',
      () async {
        final rawController = StreamController<Uint8List>();
        when(
          () => mockRecorder.startStream(any()),
        ).thenAnswer((_) async => rawController.stream);

        final events = <Uint8List>[];
        final sub = dataSource.stream().listen(events.add);

        // laisse le temps à _startRecording() (async) de s'exécuter
        await Future<void>.delayed(Duration.zero);

        final captured = verify(
          () => mockRecorder.startStream(captureAny()),
        ).captured;
        final config = captured.single as RecordConfig;
        expect(config.encoder, AudioEncoder.pcm16bits);
        expect(config.sampleRate, AudioConstants.sampleRate);
        expect(config.numChannels, 1);

        // un seul buffer complet (bufferSize*2 bytes) doit être émis
        // après avoir fourni exactement ce volume de données brutes
        final chunk = Uint8List(AudioConstants.bufferSize * 2);
        rawController.add(chunk);
        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events.single.length, AudioConstants.bufferSize * 2);

        await sub.cancel();
        await rawController.close();
      },
    );

    test('relaie les erreurs du flux brut vers le stream exposé', () async {
      final rawController = StreamController<Uint8List>();
      when(
        () => mockRecorder.startStream(any()),
      ).thenAnswer((_) async => rawController.stream);

      final errors = <Object>[];
      final sub = dataSource.stream().listen((_) {}, onError: errors.add);
      await Future<void>.delayed(Duration.zero);

      rawController.addError(StateError('capture perdue'));
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());

      await sub.cancel();
      await rawController.close();
    });
  });

  group('dispose', () {
    test(
      'annule l\'abonnement et arrête/libère le recorder après un stream() actif',
      () async {
        final rawController = StreamController<Uint8List>();
        when(
          () => mockRecorder.startStream(any()),
        ).thenAnswer((_) async => rawController.stream);
        when(() => mockRecorder.stop()).thenAnswer((_) async => null);
        when(() => mockRecorder.dispose()).thenAnswer((_) async {});

        final sub = dataSource.stream().listen((_) {});
        await Future<void>.delayed(Duration.zero);

        await dataSource.dispose();

        verify(() => mockRecorder.stop()).called(1);
        verify(() => mockRecorder.dispose()).called(1);

        await sub.cancel();
        await rawController.close();
      },
    );

    test(
      'ne lance pas si dispose() est appelé sans stream() préalable',
      () async {
        when(() => mockRecorder.stop()).thenAnswer((_) async => null);
        when(() => mockRecorder.dispose()).thenAnswer((_) async {});

        await expectLater(dataSource.dispose(), completes);
      },
    );

    test(
      'stream() reste écoutable après un cycle dispose() (réutilisation '
      'start/stop — ex. pause/reprise, changement d\'onglet)',
      () async {
        // Un Stream Dart à abonnement unique ne peut être écouté qu'une
        // seule fois dans toute sa vie, même après cancel/close. Comme
        // AudioRepositoryImpl/ChordRepositoryImpl réutilisent la même
        // instance de RecordMicrophoneDataSource sur plusieurs cycles
        // start/stop, stream() doit rester utilisable après un dispose().
        when(
          () => mockRecorder.startStream(any()),
        ).thenAnswer((_) async => const Stream<Uint8List>.empty());
        when(() => mockRecorder.stop()).thenAnswer((_) async => null);
        when(() => mockRecorder.dispose()).thenAnswer((_) async {});

        final sub1 = dataSource.stream().listen((_) {});
        await Future<void>.delayed(Duration.zero);
        await dataSource.dispose();
        await sub1.cancel();

        // 2e cycle : ne doit pas lancer "Bad state: Stream has already
        // been listened to."
        expect(() => dataSource.stream().listen((_) {}), returnsNormally);
      },
    );
  });
}
