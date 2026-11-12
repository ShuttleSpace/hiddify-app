import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_desktop.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

/// OpenHarmony / HarmonyOS.
///
/// The tunnel is the vNIC of a `type: "vpn"` extension ability, which always
/// runs in its own process and in its own SELinux domain (`vpn_isolate_hap`).
/// The vNIC descriptor cannot leave that process, so the core has to run there,
/// driven from here over the loopback interface; see
/// docs/superpowers/plans/2026-11-10-ohos-vpn-spike-results.md.
///
/// The class also carries the diagnostic that settles whether the core library
/// loads in this process at all: it is a Go c-shared library, and on aarch64 its
/// initial-exec TLS relocation is refused by the loader of a runtime-loaded
/// library, so the FFI path of [CoreInterfaceDesktop] does not work here.
/// Diagnostic: tries to load the core library in this process and returns the
/// error, or null when it loaded.
String? probeCoreLibraryLoad() {
  try {
    DynamicLibrary.open('libhiddify-core.so');
    return null;
  } catch (error) {
    return error.toString();
  }
}

class CoreInterfaceOhos extends CoreInterfaceDesktop {
  CoreInterfaceOhos() : super(port: 17078) {
    unawaited(_writeProbe());
  }

  /// Writes the result of loading the core library into the app's sandbox, so
  /// that the VPN extension process (which shares the sandbox) can report it:
  /// Dart's own output does not reach hilog.
  Future<void> _writeProbe() async {
    final probe = loadProbe();
    final message = 'ohos core library load probe: ${probe ?? 'loaded'}';
    loggy.info(message);
    try {
      final directory = await getApplicationDocumentsDirectory();
      await File('${directory.path}/ohos_core_probe.txt').writeAsString(message);
    } catch (error) {
      loggy.warning('could not write the load probe: $error');
    }
  }

  /// Diagnostic: can this process load the core library at all? The core is a
  /// Go c-shared library, and its initial-exec TLS only works when it is
  /// loaded before the process has used up its static TLS surplus.
  static String? loadProbe() => probeCoreLibraryLoad();

  /// ArkTS side: HiddifyVpnPlugin.ets.
  static const MethodChannel _channel = MethodChannel('hiddify/vpn');

  final _status = BehaviorSubject<CoreStatus>.seeded(const CoreStatus.stopped());

  SingboxConfigOption? _options;

  @override
  bool get managesLifecycle => true;

  @override
  Stream<CoreStatus> get managedStatus => _status.stream;

  /// Whether the system keeps a VPN profile for the app that [resetTunnel] can remove.
  @override
  bool get hasVpnProfile => true;

  @override
  Future<void> setOptions(SingboxConfigOption options) async {
    _options = options;
    final response = await fgClient.changeHiddifySettings(
      ChangeHiddifySettingsRequest(hiddifySettingsJson: jsonEncode(options.toJson())),
    );
    _checkResponse(response);
  }

  @override
  Future<void> startManaged(String path, String name, bool disableMemoryLimit) async {
    final options = _options;
    if (options == null) throw StateError('Apply connection options before starting the core.');
    await stop();

    _status.add(const CoreStatus.starting());
    try {
      if (options.enableTun) {
        // The fd has to be in the core before the box starts: the tun inbound
        // opens the interface while the box is being built.
        final fd = await _startVpnAndInjectTunFd();
        _checkResponse(
          await startOnceStopped(
            fgClient,
            StartRequest(configPath: path, configName: name, disableMemoryLimit: disableMemoryLimit),
          ),
        );
        loggy.info('OHOS VPN tunnel started with fd $fd');
      } else {
        _checkResponse(
          await startOnceStopped(
            fgClient,
            StartRequest(configPath: path, configName: name, disableMemoryLimit: disableMemoryLimit),
          ),
        );
      }
      _status.add(const CoreStatus.started());
    } catch (error) {
      _status.add(CoreStatus.stopped(message: error.toString()));
      rethrow;
    }
  }

  /// Starts the VPN extension and injects the vNIC descriptor into the core.
  Future<int> _startVpnAndInjectTunFd() async {
    final fd = await _channel.invokeMethod<int>('startVpn');
    if (fd == null || fd <= 0) {
      throw StateError('The VPN extension did not return a tun file descriptor.');
    }
    CoreInterfaceDesktop.nativeLibrary.SetupTun(fd);
    return fd;
  }

  @override
  Future<bool> stop() async {
    _status.add(const CoreStatus.stopping());
    try {
      // Clears the injected descriptor, so a later start without a VPN fails
      // loudly instead of picking up a closed descriptor.
      CoreInterfaceDesktop.nativeLibrary.SetupTun(0);
      await _channel.invokeMethod<void>('stopVpn');
    } catch (error) {
      loggy.warning('stopping the OHOS VPN extension failed: $error');
    }
    try {
      await fgClient.stop(Empty()).timeout(const Duration(seconds: 5));
    } catch (error) {
      loggy.warning('stopping the in-process core failed: $error');
    }
    _status.add(const CoreStatus.stopped());
    return true;
  }

  @override
  Future<bool> resetTunnel() async {
    await stop();
    return true;
  }

  void _checkResponse(CoreInfoResponse response, {bool allowStopped = false}) {
    if (response.messageType != MessageType.EMPTY &&
        response.messageType != MessageType.ALREADY_STARTED &&
        !(allowStopped && response.messageType == MessageType.ALREADY_STOPPED)) {
      throw StateError('${response.messageType}: ${response.message}');
    }
  }
}
