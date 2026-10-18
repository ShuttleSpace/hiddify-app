import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';

class AppPackageMetadataRepository {
  static const _channel = MethodChannel('com.hiddify.app/platform');

  Future<List<AppPackageInfo>> getInstalledApps() async {
    final raw = await _channel.invokeMethod<String>('get_installed_packages');
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    final apps = <AppPackageInfo>[];
    for (final item in decoded) {
      final map = item as Map<dynamic, dynamic>;
      apps.add(
        AppPackageInfo(
          packageName: map['package-name'] as String,
          name: map['name'] as String,
          icon: null,
          isSystemApp: map['is-system-app'] as bool? ?? false,
          hasInternetPermission: map['has-internet-permission'] as bool? ?? false,
        ),
      );
    }
    return apps;
  }

  Future<Uint8List?> getIcon(String packageName) async {
    final base64 = await _channel.invokeMethod<String>(
      'get_package_icon',
      {'packageName': packageName},
    );
    return base64 == null ? null : base64Decode(base64);
  }
}
