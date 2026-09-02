import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../core/constants/audio_constants.dart';
import '../../domain/exceptions/audio_permission_exception.dart';
import 'audio_buffer_accumulator.dart';
import 'microphone_data_source.dart';

class RecordMicrophoneDataSource implements MicrophoneDataSource {
  RecordMicrophoneDataSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final _accumulator = AudioBufferAccumulator(
    AudioConstants.bufferSize * 2,
  ); // N × 2 bytes
  // Recréé à chaque stream() (cf. plus bas) — pas final : un Stream Dart à
  // abonnement unique ne peut être écouté qu'une seule fois dans toute sa
  // vie, même après cancel/close. Cette instance est réutilisée sur
  // plusieurs cycles start/stop (pause/reprise, changement d'onglet) par
  // AudioRepositoryImpl/ChordRepositoryImpl — contrairement à AudioRecorder
  // (voir stream() ci-dessous), un StreamController figé ne survivrait pas
  // à un 2e cycle.
  StreamController<Uint8List>? _controller;
  StreamSubscription<Uint8List>? _subscription;

  @override
  Future<void> initialize() async {
    final status = await Permission.microphone.status;
    if (status.isPermanentlyDenied) {
      throw const AudioPermissionException(isPermanent: true);
    }
    final requested = await Permission.microphone.request();
    if (requested.isDenied || requested.isPermanentlyDenied) {
      throw AudioPermissionException(
        isPermanent: requested.isPermanentlyDenied,
      );
    }
  }

  @override
  Stream<Uint8List> stream() {
    final controller = StreamController<Uint8List>();
    _controller = controller;
    _startRecording(controller);
    return controller.stream;
  }

  Future<void> _startRecording(StreamController<Uint8List> controller) async {
    final rawStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AudioConstants.sampleRate,
        numChannels: 1,
      ),
    );
    _subscription = rawStream.listen(
      (chunk) {
        for (final buf in _accumulator.feed(chunk)) {
          controller.add(buf);
        }
      },
      onError: controller.addError,
      cancelOnError: false,
    );
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();
    await _recorder.dispose();
    _accumulator.clear();

    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    // close() retourne un Future qui attend la livraison du `done` à chaque
    // abonné. Sans abonné (dispose() appelé sans stream() préalable) ce
    // Future ne se complète JAMAIS → on n'awaite pas dans ce cas.
    if (controller.hasListener) {
      await controller.close();
    } else {
      unawaited(controller.close());
    }
  }
}
