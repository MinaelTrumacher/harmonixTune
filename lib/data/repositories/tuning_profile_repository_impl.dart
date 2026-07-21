import 'dart:async';

import 'package:hive/hive.dart';

import '../../domain/entities/tuning_profile.dart';
import '../../domain/repositories/tuning_profile_repository.dart';
import '../models/tuning_profile_model.dart';

class TuningProfileRepositoryImpl implements TuningProfileRepository {
  TuningProfileRepositoryImpl(this._box);

  final Box<TuningProfileModel> _box;

  List<TuningProfile> _currentValues() =>
      _box.values.map((model) => model.toEntity()).toList(growable: false);

  @override
  Stream<List<TuningProfile>> watchAll() {
    late final StreamController<List<TuningProfile>> controller;
    StreamSubscription<BoxEvent>? boxSubscription;

    controller = StreamController<List<TuningProfile>>(
      onListen: () {
        controller.add(_currentValues());
        boxSubscription = _box.watch().listen(
          (_) => controller.add(_currentValues()),
        );
      },
      onCancel: () async {
        await boxSubscription?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Future<TuningProfile?> getById(String id) async {
    return _box.get(id)?.toEntity();
  }

  @override
  Future<void> save(TuningProfile profile) async {
    await _box.put(profile.id, TuningProfileModel.fromEntity(profile));
  }

  @override
  Future<void> delete(String id) async {
    await _box.delete(id);
  }
}
