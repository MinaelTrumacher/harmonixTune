import 'bootstrap.dart';
import 'core/config/flavor.dart';

// Alias de confort pour `flutter run` sans -t : équivaut à main_prod.dart.
// Une fois les flavors Android en place, utiliser explicitement
// --flavor <dev|staging|prod> -t lib/main_<flavor>.dart.
Future<void> main() => bootstrap(Flavor.prod);
