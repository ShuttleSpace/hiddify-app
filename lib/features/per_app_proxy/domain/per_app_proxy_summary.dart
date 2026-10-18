import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';

class PerAppProxySummary {
  const PerAppProxySummary({
    required this.active,
    required this.userSelected,
    required this.autoSelected,
    required this.forceDeselected,
  });

  final int active;
  final int userSelected;
  final int autoSelected;
  final int forceDeselected;
}

PerAppProxySummary computePerAppProxySummary(Map<String, int> flags) {
  var active = 0;
  var userSelected = 0;
  var autoSelected = 0;
  var forceDeselected = 0;

  for (final flag in flags.values) {
    if (PkgFlag.checkboxValue(flag) != false) active += 1;
    if (PkgFlag.userSelection.check(flag)) userSelected += 1;
    if (PkgFlag.autoSelection.check(flag) &&
        !PkgFlag.forceDeselection.check(flag)) {
      autoSelected += 1;
    }
    if (PkgFlag.forceDeselection.check(flag)) forceDeselected += 1;
  }

  return PerAppProxySummary(
    active: active,
    userSelected: userSelected,
    autoSelected: autoSelected,
    forceDeselected: forceDeselected,
  );
}
