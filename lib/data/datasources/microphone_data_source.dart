import 'dart:typed_data';

abstract interface class MicrophoneDataSource {
  /// Demande la permission microphone et configure la capture.
  /// Lance [AudioPermissionException] si l'accès est refusé.
  Future<void> initialize();

  /// Stream de buffers PCM 16-bit mono @ 44 100 Hz, taille fixe
  /// [AudioConstants.bufferSize] samples (4 096 bytes).
  Stream<Uint8List> stream();

  Future<void> dispose();
}
