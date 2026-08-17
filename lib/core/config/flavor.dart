enum Flavor { dev, staging, prod }

// Point d'accès global au flavor courant — fixé une seule fois par
// l'entrypoint (main_dev/main_staging/main_prod.dart) avant tout autre appel.
abstract final class FlavorConfig {
  static Flavor flavor = Flavor.prod;

  static String get label => switch (flavor) {
    Flavor.dev => 'DEV',
    Flavor.staging => 'STAGING',
    Flavor.prod => 'PROD',
  };

  static bool get isProd => flavor == Flavor.prod;
}
