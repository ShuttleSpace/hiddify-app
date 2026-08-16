import 'package:flutter/foundation.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PlatformCapabilities {
  const PlatformCapabilities();

  bool get supportsTray => PlatformUtils.isDesktop;

  bool get supportsTraySpeedIndicator => supportsTray && !PlatformUtils.isLinux;

  bool get supportsGlobalHotkeys => supportsTray;

  bool get supportsSecureStorage => !kIsWeb;

  bool get supportsDynamicColor => PlatformUtils.isMobile || PlatformUtils.isDesktop;

  bool get supportsFileExport => !kIsWeb;

  bool get supportsBackgroundBackup => PlatformUtils.isDesktop || PlatformUtils.isMobile;
}

final platformCapabilitiesProvider = Provider<PlatformCapabilities>((ref) => const PlatformCapabilities());
