import 'package:dartx/dartx.dart';

enum Environment {
  prod,
  dev;

  static const localDSN = 'http://7310028e8a5345888bb9779abd177259@localhost:8000/1';
  static const sentryDSN = String.fromEnvironment("sentry_dsn");
  // This environment variable is set in the 'windows-release-zip' command
  static const isPortable = bool.fromEnvironment("portable");
}

enum Release {
  general("general"),
  // This environment variable is set in the 'android-release-aab' command
  googlePlay("google-play");

  const Release(this.key);

  final String key;

  bool get allowCustomUpdateChecker => this == general;

  static Release read() =>
      Release.values.firstOrNullWhere((e) => e.key == const String.fromEnvironment("release")) ?? Release.general;
}
