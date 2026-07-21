import '../entities/pitch_result.dart';
import '../entities/tuning_configuration.dart';

abstract interface class AudioRepository {
  Stream<PitchResult> streamPitch(TuningConfiguration config);
  Future<void> updateConfig(TuningConfiguration config);
  Future<void> stop();
}
