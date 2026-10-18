import 'dart:typed_data';

class AppPackageInfo {
  const AppPackageInfo({
    required this.packageName,
    required this.name,
    required this.icon,
    this.isSystemApp = false,
    this.hasInternetPermission = false,
  });

  final String packageName;
  final String name;
  final Uint8List? icon;
  final bool isSystemApp;
  final bool hasInternetPermission;
}
