import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../domain/entities/pitch_result.dart';
import '../../domain/entities/tuning_configuration.dart';
import '../../domain/exceptions/audio_permission_exception.dart';
import '../../domain/repositories/audio_repository.dart';
import '../datasources/microphone_data_source.dart';
import '../workers/audio_isolate_worker.dart';

class AudioRepositoryImpl implements AudioRepository {
  AudioRepositoryImpl(this._dataSource);

  final MicrophoneDataSource _dataSource;

  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _mainPort;
  StreamSubscription<Uint8List>? _micSubscription;
  StreamController<PitchResult>? _controller;
  bool _disposed = false;

  @override
  Stream<PitchResult> streamPitch(TuningConfiguration config) {
    _disposed = false;
    // onListen : _start() n'est déclenché QUE quand un abonné écoute.
    // Cela évite de spawner un Isolate en pure fire-and-forget
    // (difficile à tuer proprement si stop() arrive avant la fin du spawn).
    _controller = StreamController<PitchResult>(
      onListen: () => _start(config),
      onCancel: stop,
    );
    return _controller!.stream;
  }

  Future<void> _start(TuningConfiguration config) async {
    try {
      await _dataSource.initialize();

      _mainPort = ReceivePort();
      _isolate = await Isolate.spawn(
        audioIsolateEntryPoint,
        _mainPort!.sendPort,
      );

      _mainPort!.listen((message) {
        if (message is SendPort) {
          _workerPort = message;
          _workerPort!.send(InitWorkerMessage(config));
          _micSubscription = _dataSource.stream().listen(
            (chunk) => _workerPort?.send(
              AudioBufferMessage(TransferableTypedData.fromList([chunk])),
            ),
            onError: (Object error, StackTrace stack) {
              _controller?.addError(error, stack);
              stop();
            },
            cancelOnError: true,
          );
        } else if (message is PitchDetectedMessage) {
          if (!(_controller?.isClosed ?? true)) {
            _controller?.add(message.result);
          }
        }
      });
    } on AudioPermissionException catch (e) {
      _controller?.addError(e);
    } catch (e, s) {
      _controller?.addError(e, s);
    }
  }

  @override
  Future<void> updateConfig(TuningConfiguration config) async {
    _workerPort?.send(UpdateConfigMessage(config));
  }

  @override
  Future<void> stop() => _cleanup();

  Future<void> _cleanup() async {
    if (_disposed) return;
    _disposed = true;

    final sub = _micSubscription;
    _micSubscription = null;
    await sub?.cancel();

    final port = _workerPort;
    _workerPort = null;
    port?.send(const KillWorkerMessage());

    final iso = _isolate;
    _isolate = null;
    iso?.kill(priority: Isolate.immediate);

    _mainPort?.close();
    _mainPort = null;

    await _dataSource.dispose();

    final ctrl = _controller;
    _controller = null;
    // close() retourne un Future qui attend la livraison du `done` à chaque
    // abonné. Sans abonné ce Future ne se complète JAMAIS → on n'awaite pas.
    if (ctrl != null && ctrl.hasListener) {
      await ctrl.close();
    } else {
      ctrl?.close();
    }
  }
}
