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
  final _controller = StreamController<Uint8List>();
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
    _startRecording();
    return _controller.stream;
  }

  Future<void> _startRecording() async {
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
          _controller.add(buf);
        }
      },
      onError: _controller.addError,
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
    await _controller.close();
  }
}
