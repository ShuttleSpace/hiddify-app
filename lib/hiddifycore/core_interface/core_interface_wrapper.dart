import 'dart:io';

import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_desktop.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_desktop_tun.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_macos.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_mobile.dart';

CoreInterface getCoreInterface() {
  if (Platform.isAndroid || Platform.isIOS) {
    return CoreInterfaceMobile();
  }
  if (Platform.isMacOS) return CoreInterfaceMacOS();
  if (Platform.isWindows || Platform.isLinux) return CoreInterfaceDesktopTun();
  // OpenHarmony/HarmonyOS: the core runs as a c-shared library loaded via FFI
  // (no system tunnel service yet — the VPN extension is a separate TODO), so the
  // desktop interface (gRPC control plane) is the right one.
  return CoreInterfaceDesktop();
}
