import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../core/constants/audio_constants.dart';
import '../../domain/entities/chord_result.dart';
import '../../domain/exceptions/audio_permission_exception.dart';
import '../../domain/repositories/chord_repository.dart';
import '../datasources/microphone_data_source.dart';
import '../workers/chord_isolate_worker.dart';

/// Miroir de `AudioRepositoryImpl` : possède sa propre `MicrophoneDataSource`
/// et son propre Isolate, indépendants de ceux du Tuner (§3.1 —
/// `docs/STRATEGIE_DETECTION_ACCORDS.md`). Tuner et Chords ne sont jamais
/// actifs simultanément (un seul onglet visible à la fois), donc aucune
/// mutualisation n'est nécessaire.
class ChordRepositoryImpl implements ChordRepository {
  ChordRepositoryImpl(this._dataSource);

  final MicrophoneDataSource _dataSource;

  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _mainPort;
  StreamSubscription<Uint8List>? _micSubscription;
  StreamController<ChordResult>? _controller;
  bool _disposed = false;

  @override
  Stream<ChordResult> streamChord({
    double referenceA4Hz = AudioConstants.referenceA4Hz,
  }) {
    _disposed = false;
    // onListen : _start() n'est déclenché QUE quand un abonné écoute — évite
    // de spawner un Isolate en pure fire-and-forget (cf. AudioRepositoryImpl).
    _controller = StreamController<ChordResult>(
      onListen: () => _start(referenceA4Hz),
      onCancel: stop,
    );
    return _controller!.stream;
  }

  Future<void> _start(double referenceA4Hz) async {
    try {
      await _dataSource.initialize();

      _mainPort = ReceivePort();
      _isolate = await Isolate.spawn(
        chordIsolateEntryPoint,
        _mainPort!.sendPort,
      );

      _mainPort!.listen((message) {
        if (message is SendPort) {
          _workerPort = message;
          _workerPort!.send(
            InitChordWorkerMessage(referenceA4Hz: referenceA4Hz),
          );
          _micSubscription = _dataSource.stream().listen(
            (chunk) => _workerPort?.send(
              ChordAudioBufferMessage(TransferableTypedData.fromList([chunk])),
            ),
            onError: (Object error, StackTrace stack) {
              _controller?.addError(error, stack);
              stop();
            },
            cancelOnError: true,
          );
        } else if (message is ChordDetectedMessage) {
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
  Future<void> stop() => _cleanup();

  Future<void> _cleanup() async {
    if (_disposed) return;
    _disposed = true;

    final sub = _micSubscription;
    _micSubscription = null;
    await sub?.cancel();

    final port = _workerPort;
    _workerPort = null;
    port?.send(const KillChordWorkerMessage());

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
