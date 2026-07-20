import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/config/flavor.dart';
import 'data/models/tuning_profile_model.dart';
import 'data/repositories/tuning_profile_repository_impl.dart';
import 'firebase_options.dart';
import 'presentation/app.dart';

// Point d'entrée commun aux 3 entrypoints (main_dev/main_staging/main_prod).
// `flavor` détermine uniquement FlavorConfig ici : Crashlytics/Performance
// pointent sur le même projet Firebase pour les 3 environnements (cf.
// docs/MONITORING_SETUP.md) — seul l'applicationId Android varie.
Future<void> bootstrap(Flavor flavor) async {
  FlavorConfig.flavor = flavor;

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

      await Hive.initFlutter();
      Hive.registerAdapter(TuningProfileModelAdapter());
      final tuningProfileBox = await Hive.openBox<TuningProfileModel>(
        'tuning_profiles',
      );

      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(!kDebugMode);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      runApp(
        HarmonixTuneApp(
          tuningProfileRepository: TuningProfileRepositoryImpl(
            tuningProfileBox,
          ),
        ),
      );
    },
    (error, stack) => FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
  );
}
