import 'dart:io';

import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_desktop.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_desktop_tun.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_macos.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_mobile.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_ohos.dart';

CoreInterface getCoreInterface() {
  if (Platform.isAndroid || Platform.isIOS) {
    return CoreInterfaceMobile();
  }
  if (Platform.isMacOS) return CoreInterfaceMacOS();
  if (Platform.isWindows || Platform.isLinux) return CoreInterfaceDesktopTun();
  // OpenHarmony/HarmonyOS: the core runs as a c-shared library loaded via FFI,
  // and the tunnel is the vNIC of a VPN extension ability, whose descriptor is
  // relayed into this process.
  if (Platform.operatingSystem == 'ohos') return CoreInterfaceOhos();
  return CoreInterfaceDesktop();
}
