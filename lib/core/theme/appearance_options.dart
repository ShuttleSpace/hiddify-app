import 'package:hiddify/core/utils/preferences_utils.dart';

enum AppTextScaleMode {
  system(1),
  small(.85),
  standard(1),
  large(1.15),
  extraLarge(1.3);

  const AppTextScaleMode(this.scale);

  final double scale;
}

enum AppColorSource { brand, dynamicColor, seed }

abstract class AppearanceOptions {
  static final textScaleMode = PreferencesNotifier.create<AppTextScaleMode, String>(
    'appearance-text-scale-mode',
    AppTextScaleMode.system,
    mapFrom: AppTextScaleMode.values.byName,
    mapTo: (value) => value.name,
  );

  static final colorSource = PreferencesNotifier.create<AppColorSource, String>(
    'appearance-color-source',
    AppColorSource.brand,
    mapFrom: AppColorSource.values.byName,
    mapTo: (value) => value.name,
  );

  static final seedColorValue = PreferencesNotifier.create<int, int>(
    'appearance-seed-color',
    0xFF293CA0,
    validator: (value) => value >= 0 && value <= 0xFFFFFFFF,
  );
}
