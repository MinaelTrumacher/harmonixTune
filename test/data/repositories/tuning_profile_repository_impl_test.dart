import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:harmonix_tune/data/models/tuning_profile_model.dart';
import 'package:harmonix_tune/data/repositories/tuning_profile_repository_impl.dart';
import 'package:harmonix_tune/domain/entities/tuning_profile.dart';
import 'package:harmonix_tune/domain/enums/instrument_type.dart';

TuningProfile _openG() => const TuningProfile(
  id: 'p1',
  name: 'Open G Keith Richards',
  instrumentType: InstrumentType.guitar,
  stringNotes: ['D2', 'G2', 'D3', 'G3', 'B3', 'D4'],
);

void main() {
  late Directory tempDir;
  late Box<TuningProfileModel> box;
  late TuningProfileRepositoryImpl repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_tuning_profile_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(TuningProfileModelAdapter());
    }
    box = await Hive.openBox<TuningProfileModel>('tuning_profiles_test');
    repo = TuningProfileRepositoryImpl(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('tuning_profiles_test', path: tempDir.path);
    await tempDir.delete(recursive: true);
  });

  group('TuningProfileRepositoryImpl — save / getById', () {
    test('save puis getById retourne un profil équivalent', () async {
      await repo.save(_openG());
      final loaded = await repo.getById('p1');
      expect(loaded, equals(_openG()));
    });

    test('getById sur un id absent retourne null', () async {
      expect(await repo.getById('inconnu'), isNull);
    });

    test('save écrase un profil existant portant le même id', () async {
      await repo.save(_openG());
      await repo.save(_openG().copyWith(name: 'Renommé'));
      final loaded = await repo.getById('p1');
      expect(loaded!.name, 'Renommé');
    });
  });

  group('TuningProfileRepositoryImpl — delete', () {
    test('delete retire le profil de la base', () async {
      await repo.save(_openG());
      await repo.delete('p1');
      expect(await repo.getById('p1'), isNull);
    });

    test('delete sur un id absent ne lève pas d\'exception', () async {
      await expectLater(repo.delete('inconnu'), completes);
    });
  });

  group('TuningProfileRepositoryImpl — watchAll (réactivité Local-First)', () {
    test('émet la liste courante dès l\'abonnement', () async {
      await repo.save(_openG());
      final first = await repo.watchAll().first;
      expect(first, equals([_openG()]));
    });

    test('émet une liste vide si la base est vide', () async {
      final first = await repo.watchAll().first;
      expect(first, isEmpty);
    });

    test('émet une nouvelle liste après un save ultérieur', () async {
      final emissions = <List<TuningProfile>>[];
      final sub = repo.watchAll().listen(emissions.add);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.save(_openG());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last, equals([_openG()]));

      await sub.cancel();
    });

    test('émet une nouvelle liste après un delete', () async {
      await repo.save(_openG());

      final emissions = <List<TuningProfile>>[];
      final sub = repo.watchAll().listen(emissions.add);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.delete('p1');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.last, isEmpty);

      await sub.cancel();
    });
  });
}
