/**
 * Flutter side of the OHOS VPN control channel.
 *
 * Lives in the main (Flutter) process; the core and the tunnel run in the
 * `<bundle>:vpn` extension process, because the vNIC descriptor cannot leave
 * that process's SELinux domain. This channel starts the extension, passes it
 * the core's configuration, and waits until the core's gRPC server answers.
 */
import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import vpnExtension from '@ohos.net.vpnExtension';
import type Want from '@ohos.app.ability.Want';
import hilog from '@ohos.hilog';
import fs from '@ohos.file.fs';
import socket from '@ohos.net.socket';

import { readRelayedFd, receiveTunFd, TUN_FD_TIMEOUT_MS, TUN_SOCKET_NAME } from './VpnFdRelay';
import { coreIsMapped, coreLibraryPath, lastError, loadCore } from './VpnCoreHost';

const TAG: string = 'HIDDIFY_VPN';
const DOMAIN: number = 0x0000;
const CHANNEL: string = 'hiddify/vpn';
const VPN_ABILITY_NAME: string = 'HiddifyVpnExtension';

/**
 * Launch parameter that turns on the relay probe: the app process waits for a
 * descriptor the extension process sends, and reports whether it arrived and
 * is readable. It proves the cross-process fd relay without needing the VPN
 * system API (which needs a system-app profile).
 */
const RELAY_PROBE: string = 'vpnRelayProbe';

/** How long to wait for the core's gRPC server to come up. */
const CORE_READY_TIMEOUT_MS: number = 30000;

export default class HiddifyVpnPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private methodChannel: MethodChannel | null = null;
  private binding: FlutterPluginBinding | null = null;
  private abilityBinding: AbilityPluginBinding | null = null;

  getUniqueClassName(): string {
    return 'HiddifyVpnPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.binding = binding;
    this.methodChannel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.methodChannel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.methodChannel?.setMethodCallHandler(null);
    this.methodChannel = null;
    this.binding = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding;
    // The same probe as in the extension process: the core is a Go c-shared
    // library and can only be loaded before the process has used up its static
    // TLS surplus.
    const context = binding.getAbility().context;
    const libraryPath: string = coreLibraryPath(context.bundleCodeDir);
    const loaded: number = loadCore(libraryPath);
    hilog.info(DOMAIN, TAG, 'main core load=%{public}d mapped=%{public}d err=%{public}s',
      loaded, coreIsMapped(), lastError());
    const parameters = binding.getAbility().launchWant.parameters;
    if (parameters !== undefined && parameters[RELAY_PROBE] === true) {
      this.probeRelay();
    }
  }

  onDetachedFromAbility(): void {
    this.abilityBinding = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'startVpn') {
      this.startVpn(call, result);
    } else if (call.method === 'stopVpn') {
      this.stopVpn(result);
    } else if (call.method === 'coreLoadProbe') {
      hilog.info(DOMAIN, TAG, 'dart core load probe: %{public}s', String(call.argument('result')));
      result.success(null);
    } else {
      result.notImplemented();
    }
  }

  /**
   * Starts the VPN extension, which starts the core in its own process, and
   * resolves once the core's gRPC server answers on the loopback interface.
   */
  private async startVpn(call: MethodCall, result: MethodResult): Promise<void> {
    const listen: string = String(call.argument('coreListen'));
    const host: string = listen.includes(':') ? listen.split(':')[0] : '127.0.0.1';
    const port: number = Number(listen.split(':')[1]);

    const want: Want = {
      bundleName: 'app.hiddify.com',
      abilityName: VPN_ABILITY_NAME,
      parameters: {
        coreListen: listen,
        coreSecret: String(call.argument('coreSecret')),
        coreBaseDir: String(call.argument('coreBaseDir')),
        coreWorkingDir: String(call.argument('coreWorkingDir')),
        coreTempDir: String(call.argument('coreTempDir')),
        coreMode: Number(call.argument('coreMode')),
        coreEnableTun: call.argument('coreEnableTun') === true,
        coreDebug: call.argument('coreDebug') === true
      }
    };
    try {
      await vpnExtension.startVpnExtensionAbility(want);
      hilog.info(DOMAIN, TAG, 'vpn extension started, waiting for the core on %{public}s', listen);
      const ready = await this.waitForPort(host, port, CORE_READY_TIMEOUT_MS);
      if (!ready) {
        result.error('core_not_ready', 'The core did not start listening on ' + listen, null);
        return;
      }
      result.success(listen);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'startVpn failed: %{public}s', error.message);
      result.error('vpn_start_failed', 'Could not start the VPN extension.', error.message);
    }
  }

  /** Waits until something accepts a connection on the loopback port. */
  private async waitForPort(host: string, port: number, timeoutMs: number): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      let client: socket.TCPSocket | null = null;
      try {
        client = socket.constructTCPSocketInstance();
        await client.connect({ address: { address: host, port: port, family: 1 }, timeout: 2000 });
        return true;
      } catch (error) {
        // Not up yet.
      } finally {
        if (client !== null) {
          try {
            client.close();
          } catch (_) {
          }
        }
      }
      await new Promise<void>((resolve) => setTimeout(() => resolve(), 200));
    }
    return false;
  }

  private async stopVpn(result: MethodResult): Promise<void> {
    const want: Want = {
      bundleName: 'app.hiddify.com',
      abilityName: VPN_ABILITY_NAME
    };
    try {
      await vpnExtension.stopVpnExtensionAbility(want);
      result.success(null);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'stopVpn failed: %{public}s', error.message);
      result.error('vpn_stop_failed', 'Could not stop the VPN extension.', error.message);
    }
  }

  /** Diagnostic: wait for a descriptor from the extension process and read it. */
  private async probeRelay(): Promise<void> {
    const binding = this.binding;
    if (binding === null) {
      return;
    }
    const socketName = TUN_SOCKET_NAME;
    hilog.info(DOMAIN, TAG, 'relay probe: waiting for a descriptor on %{public}s', socketName);
    try {
      const fd: number = await receiveTunFd(socketName, TUN_FD_TIMEOUT_MS);
      hilog.info(DOMAIN, TAG, 'relay probe: got fd=%{public}d', fd);
      // The core reads the descriptor with plain syscalls; ArkTS's own fs API
      // refuses a descriptor it did not open.
      const read = readRelayedFd(fd, 64);
      hilog.info(DOMAIN, TAG, 'relay probe: read %{public}d bytes from the relayed fd', read);
      fs.closeSync(fd);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'relay probe failed: %{public}s', error.message);
    }
  }
}
