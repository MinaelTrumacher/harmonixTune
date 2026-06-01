import 'dart:typed_data';

class YinDetector {
  YinDetector({
    required this.sampleRate,
    required this.bufferSize,
    this.threshold = 0.10,
  }) : _tauMin = (sampleRate / 1200.0).ceil(),
       _tauMax = bufferSize ~/ 2,
       // +1 pour accéder à _cmndf[_tauMax] lors de l'interpolation parabolique
       _cmndf = Float64List(bufferSize ~/ 2 + 1);

  final int sampleRate;
  final int bufferSize;
  final double threshold;

  final int _tauMin;
  final int _tauMax;
  final Float64List _cmndf;

  ({double f0Hz, double confidence})? detect(Float64List samples) {
    _computeCMNDF(samples);
    final tauStar = _findTauStar();
    if (tauStar == null) return null;

    // Interpolation parabolique — garde : uniquement si τ* est strictement
    // entre les bornes pour éviter l'accès hors tableau.
    double tauRefined = tauStar.toDouble();
    if (tauStar > _tauMin && tauStar < _tauMax) {
      final d0 = _cmndf[tauStar - 1];
      final d1 = _cmndf[tauStar];
      final d2 = _cmndf[tauStar + 1];
      final denom = 2.0 * (d0 - 2.0 * d1 + d2);
      if (denom.abs() > 1e-10) {
        tauRefined = tauStar + (d0 - d2) / denom;
      }
    }

    return (f0Hz: sampleRate / tauRefined, confidence: 1.0 - _cmndf[tauStar]);
  }

  // Calcule la CMNDF (Cumulative Mean Normalized Difference Function) in-place.
  // d'(0) = 1 ; d'(τ) = τ × d(τ) / Σ_{j=1}^{τ} d(j)
  void _computeCMNDF(Float64List x) {
    final W = bufferSize ~/ 2;
    _cmndf[0] = 1.0;
    double runningSum = 0.0;

    for (int tau = 1; tau <= W; tau++) {
      double d = 0.0;
      for (int t = 0; t < W; t++) {
        final diff = x[t] - x[t + tau];
        d += diff * diff;
      }
      runningSum += d;
      _cmndf[tau] = runningSum > 0.0 ? (d * tau) / runningSum : 1.0;
    }
  }

  // Trouve le premier τ* tel que CMNDF(τ*) < threshold et est un minimum local.
  int? _findTauStar() {
    int tau = _tauMin;
    while (tau < _tauMax) {
      if (_cmndf[tau] < threshold) {
        // Descend jusqu'au minimum local de cette vallée.
        while (tau + 1 < _tauMax && _cmndf[tau + 1] < _cmndf[tau]) {
          tau++;
        }
        return tau;
      }
      tau++;
    }
    return null;
  }
}
