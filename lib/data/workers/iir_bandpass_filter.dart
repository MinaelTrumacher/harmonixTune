import 'dart:math';
import 'dart:typed_data';

class IirBandpassFilter {
  IirBandpassFilter({
    required double centerHz,
    required int sampleRate,
    this.Q = 4.0,
  }) : _sampleRate = sampleRate {
    _updateCoefficients(centerHz);
  }

  final int _sampleRate;
  final double Q;

  // Coefficients normalisés (Audio EQ Cookbook — Bristow-Johnson, passe-bande
  // à gain constant dans la bande). b1 = 0 par construction.
  late double _b0, _b2;
  late double _a1, _a2;

  // État de la forme directe II transposée — maintenu entre les buffers.
  double _z1 = 0.0;
  double _z2 = 0.0;

  void updateCenter(double centerHz) {
    _updateCoefficients(centerHz);
    // Réinitialiser l'état pour éviter les transitoires et l'accumulation
    // d'erreurs numériques lors d'un changement de corde cible.
    _z1 = 0.0;
    _z2 = 0.0;
  }

  // Filtre le signal in-place. L'état (z1, z2) est conservé entre les appels
  // pour assurer la continuité entre les buffers audio successifs.
  void process(Float64List samples) {
    for (int i = 0; i < samples.length; i++) {
      final x = samples[i];
      final y = _b0 * x + _z1;
      _z1 = -_a1 * y + _z2;   // a1 est négatif → -a1 est positif (résonance)
      _z2 = _b2 * x - _a2 * y;
      samples[i] = y;
    }
  }

  void _updateCoefficients(double centerHz) {
    final omega0 = 2 * pi * centerHz / _sampleRate;
    final alpha = sin(omega0) / (2 * Q);
    final norm = 1.0 / (1.0 + alpha);

    _b0 =  alpha * norm;              //  α / (1+α)
    _b2 = -alpha * norm;              // -α / (1+α)   (b1 = 0)
    _a1 = -2.0 * cos(omega0) * norm;  // -2cos(ω₀) / (1+α)  — valeur négative
    _a2 = (1.0 - alpha) * norm;       //  (1-α) / (1+α)
  }
}
