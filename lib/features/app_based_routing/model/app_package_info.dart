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

  /// Ships with the OS image, so there is usually no reason to route it.
  final bool isSystemApp;

  /// Without this an app cannot make network requests at all, so listing it
  /// would be listing something that never touches the tunnel.
  final bool hasInternetPermission;
}
