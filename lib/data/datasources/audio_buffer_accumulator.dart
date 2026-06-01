import 'dart:typed_data';

/// Accumule des chunks audio de tailles variables et émet des buffers
/// de taille fixe [chunkBytes].
///
/// Le package `record` livre des chunks dont la taille dépend du matériel.
/// L'algorithme YIN exige une fenêtre d'exactement N échantillons.
/// Cet accumulateur garantit cette invariance.
class AudioBufferAccumulator {
  AudioBufferAccumulator(this.chunkBytes);

  final int chunkBytes;
  final _buf = <int>[];

  /// Ingère [data] et retourne zéro ou plusieurs buffers complets de taille
  /// [chunkBytes]. Les données restantes sont conservées pour l'appel suivant.
  ///
  /// Implémentation EAGER (pas sync*) : le buffer interne est mis à jour
  /// immédiatement, même si le caller n'itère pas le résultat.
  List<Uint8List> feed(Uint8List data) {
    _buf.addAll(data);
    final chunks = <Uint8List>[];
    while (_buf.length >= chunkBytes) {
      chunks.add(Uint8List.fromList(_buf.sublist(0, chunkBytes)));
      _buf.removeRange(0, chunkBytes);
    }
    return chunks;
  }

  void clear() => _buf.clear();
}
