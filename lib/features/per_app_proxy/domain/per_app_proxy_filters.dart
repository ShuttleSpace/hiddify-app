import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';

enum AppPackageFilter { all, system, nonSystem, internet, noInternet }

bool matchesAppPackageFilter(AppPackageInfo app, AppPackageFilter filter) {
  return switch (filter) {
    AppPackageFilter.all => true,
    AppPackageFilter.system => app.isSystemApp,
    AppPackageFilter.nonSystem => !app.isSystemApp,
    AppPackageFilter.internet => app.hasInternetPermission,
    AppPackageFilter.noInternet => !app.hasInternetPermission,
  };
}

List<AppPackageInfo> filterAndSearchApps(
  List<AppPackageInfo> apps,
  AppPackageFilter filter,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  return apps.where((app) {
    return matchesAppPackageFilter(app, filter) &&
        (normalizedQuery.isEmpty ||
            app.name.toLowerCase().contains(normalizedQuery));
  }).toList();
}

Set<String> packagesToToggle(
  List<AppPackageInfo> visibleApps,
  Map<String, int> flags,
  bool select,
) {
  final result = <String>{};
  for (final app in visibleApps) {
    final flag = flags[app.packageName];
    final current = PkgFlag.checkboxValue(flag ?? 0);
    if (select && current != true) result.add(app.packageName);
    if (!select && current != false) result.add(app.packageName);
  }
  return result;
}
