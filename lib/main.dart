import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'data/models/tuning_profile_model.dart';
import 'data/repositories/tuning_profile_repository_impl.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await Hive.initFlutter();
  Hive.registerAdapter(TuningProfileModelAdapter());
  final tuningProfileBox = await Hive.openBox<TuningProfileModel>(
    'tuning_profiles',
  );

  runApp(
    HarmonixTuneApp(
      tuningProfileRepository: TuningProfileRepositoryImpl(tuningProfileBox),
    ),
  );
}
