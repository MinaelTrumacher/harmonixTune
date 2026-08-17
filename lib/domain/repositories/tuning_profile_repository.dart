import '../entities/tuning_profile.dart';

abstract interface class TuningProfileRepository {
  // Flux réactif Local-First : émet la liste courante à l'abonnement puis à
  // chaque modification (save/delete), sans dépendre d'une connexion réseau.
  Stream<List<TuningProfile>> watchAll();

  Future<TuningProfile?> getById(String id);
  Future<void> save(TuningProfile profile);
  Future<void> delete(String id);
}
