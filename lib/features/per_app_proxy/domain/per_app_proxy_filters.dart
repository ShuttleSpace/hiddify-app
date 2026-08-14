import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';

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
