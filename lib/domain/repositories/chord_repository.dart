import '../../core/constants/audio_constants.dart';
import '../entities/chord_result.dart';

abstract interface class ChordRepository {
  /// [referenceA4Hz] : diapason utilisé pour l'attribution des degrés
  /// chromatiques, fixé au démarrage de l'écoute (pas de reconfiguration à
  /// chaud — contrairement à `AudioRepository.updateConfig`, aucun besoin
  /// identifié côté détection d'accords pour l'instant).
  Stream<ChordResult> streamChord({
    double referenceA4Hz = AudioConstants.referenceA4Hz,
  });

  Future<void> stop();
}
