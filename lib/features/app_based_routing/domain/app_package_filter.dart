import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/app_based_routing/model/app_package_info.dart';
import 'package:hiddify/features/app_based_routing/model/pkg_flag.dart';

enum AppPackageFilter {
  all,
  system,
  nonSystem,
  internet,
  noInternet;

  String present(Translations t) => switch (this) {
    AppPackageFilter.all => t.pages.settings.routing.generalOptions.perAppProxy.filters.all,
    AppPackageFilter.system => t.pages.settings.routing.generalOptions.perAppProxy.filters.system,
    AppPackageFilter.nonSystem => t.pages.settings.routing.generalOptions.perAppProxy.filters.nonSystem,
    AppPackageFilter.internet => t.pages.settings.routing.generalOptions.perAppProxy.filters.internet,
    AppPackageFilter.noInternet => t.pages.settings.routing.generalOptions.perAppProxy.filters.noInternet,
  };
}

bool matchesAppPackageFilter(AppPackageInfo app, AppPackageFilter filter) {
  return switch (filter) {
    AppPackageFilter.all => true,
    AppPackageFilter.system => app.isSystemApp,
    AppPackageFilter.nonSystem => !app.isSystemApp,
    AppPackageFilter.internet => app.hasInternetPermission,
    AppPackageFilter.noInternet => !app.hasInternetPermission,
  };
}

List<AppPackageInfo> filterAndSearchApps(List<AppPackageInfo> apps, AppPackageFilter filter, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  return apps
      .where(
        (app) =>
            matchesAppPackageFilter(app, filter) &&
            (normalizedQuery.isEmpty ||
                app.name.toLowerCase().contains(normalizedQuery) ||
                app.packageName.toLowerCase().contains(normalizedQuery)),
      )
      .toList();
}

/// Which of the visible apps a select-all would actually change.
///
/// An app already ticked, or explicitly unticked by auto selection, is left
/// alone: the point of select-all is everything *else*.
Set<String> packagesToToggle(List<AppPackageInfo> visibleApps, Map<String, int> flags, bool select) {
  final result = <String>{};
  for (final app in visibleApps) {
    final flag = flags[app.packageName];
    if (select) {
      if (PkgFlag.checkboxValue(flag ?? 0) != true) {
        result.add(app.packageName);
      }
    } else if (flag != null && flag != 0 && PkgFlag.checkboxValue(flag) != false) {
      result.add(app.packageName);
    }
  }
  return result;
}

/// Auto selection can overwrite a first write, so some packages need a second.
bool needsSecondSelectUpdate(int? flag) => flag != null && PkgFlag.forceDeselection.check(flag);

bool needsSecondDeselectUpdate(int? flag) =>
    flag != null &&
    PkgFlag.autoSelection.check(flag) &&
    !PkgFlag.forceDeselection.check(flag) &&
    !PkgFlag.userSelection.check(flag);

Future<List<String>> runVisibleAppBatch({
  required List<String> toggles,
  required Map<String, int> flags,
  required bool select,
  required Future<void> Function(String packageName) updatePkg,
}) async {
  final failed = <String>[];
  for (final packageName in toggles) {
    try {
      await updatePkg(packageName);
      if (select && needsSecondSelectUpdate(flags[packageName])) {
        await updatePkg(packageName);
      } else if (!select && needsSecondDeselectUpdate(flags[packageName])) {
        await updatePkg(packageName);
      }
    } catch (_) {
      failed.add(packageName);
    }
  }
  return failed;
}