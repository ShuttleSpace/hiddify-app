/**
 * OHOS VPN extension ability.
 *
 * Runs in the `<bundle>:vpn` process. It opens the virtual NIC with
 * `VpnConnection.create()` and hands the resulting file descriptor to the app
 * process over the fd relay (SCM_RIGHTS), because hiddify-core lives in the
 * Flutter process and a file descriptor is a per-process integer.
 *
 * The address, prefix and MTU must match what hiddify-core is told
 * (`v2/config/builder.go`: 172.19.0.1/28 and fdfe:dcba:9876::1/126), because
 * in injected mode the Go side does not configure the interface itself.
 */
import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import type Want from '@ohos.app.ability.Want';
import vpnExtension from '@ohos.net.vpnExtension';
import connection from '@ohos.net.connection';
import hilog from '@ohos.hilog';
import fs from '@ohos.file.fs';
import socket from '@ohos.net.socket';

import relay from 'libhiddifyvpn.so';
import { receiveTunFd, sendTunFd, TUN_SELF_TEST_SOCKET_NAME, TUN_SOCKET_NAME } from '../vpn/VpnFdRelay';
import { coreIsMapped, coreLibraryPath, execWithFd, lastError, loadCore, setupCore, setupTun } from '../vpn/VpnCoreHost';

const TAG: string = 'HIDDIFY_VPN';
const DOMAIN: number = 0x0000;

/** Must match hiddify-core's tun address (v2/config/builder.go). */
const TUN_ADDRESS: string = '172.19.0.1';
const TUN_PREFIX: number = 28;
const TUN_IPV6_ADDRESS: string = 'fdfe:dcba:9876::1';
const TUN_IPV6_PREFIX: number = 126;
const TUN_MTU: number = 1500;

export default class HiddifyVpnExtension extends VpnExtensionAbility {
  private connection: vpnExtension.VpnConnection | null = null;
  private observer: vpnExtension.VpnObserver | null = null;

  onCreate(want: Want): void {
    this.bootstrap(want).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'vpn extension failed: %{public}s', error.message);
      this.destroyConnection();
    });
  }

  private async bootstrap(want: Want): Promise<void> {
    const filesDir = this.context.filesDir;
    hilog.info(DOMAIN, TAG, 'vpn extension started (filesDir=%{public}s)', filesDir);

    // Proves the SCM_RIGHTS relay works on this device even where the VPN
    // system API is unavailable (no system-app profile). Uses its own socket path.
    await this.relaySelfTest(filesDir);

    // The VPN extension runs in its own SELinux domain (vpn_isolate_hap). If
    // the core is to live in this process, the app has to reach it over the
    // loopback interface: check that this domain may listen on it.
    this.probeTcpListener();

    const parameters = want.parameters;

    // The core runs in this process: the vNIC descriptor cannot leave the
    // extension's SELinux domain. The app process asks for it by passing the
    // address the core's gRPC server should listen on.
    if (parameters !== undefined && parameters['coreListen'] !== undefined) {
      await this.startCore(parameters);
      return;
    }

    // Relay probe: hand a plain descriptor to the app process instead of a
    // vNIC, to test the cross-process hop where the VPN API is not available.
    if (parameters !== undefined && parameters['vpnRelayProbe'] === true) {
      await this.sendProbeFd(filesDir);
      return;
    }

    // Exec probe: can this process run a binary and hand it a descriptor?
    if (parameters !== undefined && parameters['execProbe'] === true) {
      this.execProbe(filesDir);
      return;
    }

    this.observer = vpnExtension.createVpnObserver();
    this.observer.onAuthorizationResult((granted: boolean) => {
      hilog.info(DOMAIN, TAG, 'vpn authorization result: %{public}s', String(granted));
    });

    const link: connection.LinkAddress = {
      address: { address: TUN_ADDRESS, family: 1 },
      prefixLength: TUN_PREFIX
    };
    const link6: connection.LinkAddress = {
      address: { address: TUN_IPV6_ADDRESS, family: 2 },
      prefixLength: TUN_IPV6_PREFIX
    };
    const route: connection.RouteInfo = {
      interface: '',
      destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
      gateway: { address: '0.0.0.0', family: 1 },
      hasGateway: false,
      isDefaultRoute: true
    };
    const route6: connection.RouteInfo = {
      interface: '',
      destination: { address: { address: '::', family: 2 }, prefixLength: 0 },
      gateway: { address: '::', family: 2 },
      hasGateway: false,
      isDefaultRoute: true
    };
    const config: vpnExtension.VpnConfig = {
      addresses: [link, link6],
      routes: [route, route6],
      dnsAddresses: ['1.1.1.1', '8.8.8.8'],
      mtu: TUN_MTU,
      isIPv4Accepted: true,
      isIPv6Accepted: true
    };

    const conn = vpnExtension.createVpnConnection(this.context);
    this.connection = conn;
    const fd: number = await conn.create(config);
    hilog.info(DOMAIN, TAG, 'vnic created, fd=%{public}d', fd);

    const sent = await sendTunFd(TUN_SOCKET_NAME, fd);
    if (sent !== 0) {
      hilog.error(DOMAIN, TAG, 'could not relay the tun fd: %{public}d', sent);
      throw new Error(`relaying the tun fd failed with ${sent}`);
    }
    hilog.info(DOMAIN, TAG, 'tun fd relayed to the app process');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'vpn extension destroyed');
    this.destroyConnection();
  }

  /**
   * Checks that this process may listen on the loopback interface, which the
   * app process needs to reach a core running in the VPN extension.
   */
  private probeTcpListener(): void {
    const port: number = relay.probeTcpListen();
    hilog.info(DOMAIN, TAG, 'tcp probe: loopback listen result=%{public}d', port);
  }

  /**
   * Same-process round trip through both relay directions. Proves the
   * SCM_RIGHTS path on devices where the VPN system API is unavailable (no
   * system-app profile), and reports each side's errno when it fails.
   */
  private async relaySelfTest(filesDir: string): Promise<void> {
    const socketName = TUN_SELF_TEST_SOCKET_NAME;
    let receivedFd: number = -1;
    let receiveError: string = '';
    const receiving = receiveTunFd(socketName, 5000)
      .then((fd: number) => {
        receivedFd = fd;
      })
      .catch((error: Error) => {
        receiveError = error.message;
      });

    let file: fs.File | null = null;
    let sent: number = -1;
    try {
      file = fs.openSync(`${filesDir}/relay_selftest.txt`, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, 'hiddify ohos relay self test\n');
      sent = await sendTunFd(socketName, file.fd, 30);
    } finally {
      await receiving;
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
    hilog.info(
      DOMAIN,
      TAG,
      'relay self test: send=%{public}d receive fd=%{public}d error=%{public}s',
      sent,
      receivedFd,
      receiveError,
    );
  }


  /**
   * Starts hiddify-core in this process and, when the app asked for a tunnel,
   * hands it the vNIC descriptor first.
   */
  private async startCore(parameters: Record<string, Object>): Promise<void> {
    const libraryPath: string = coreLibraryPath(this.context.bundleCodeDir);
    const loaded: number = loadCore(libraryPath);
    hilog.info(DOMAIN, TAG, 'core load=%{public}d mapped=%{public}d', loaded, coreIsMapped());
    if (loaded !== 0) {
      hilog.error(DOMAIN, TAG, 'core load error: %{public}s', lastError());
    }
    if (loaded !== 0) {
      return;
    }
    const enableTun: boolean = parameters['coreEnableTun'] === true;
    if (enableTun) {
      const fd: number = await this.createVnic();
      if (fd <= 0) {
        hilog.error(DOMAIN, TAG, 'could not create the vnic');
        return;
      }
      const injected: number = setupTun(fd);
      hilog.info(DOMAIN, TAG, 'core setupTun(%{public}d) result=%{public}d', fd, injected);
    }
    const error: string = await setupCore(
      String(parameters['coreBaseDir']),
      String(parameters['coreWorkingDir']),
      String(parameters['coreTempDir']),
      Number(parameters['coreMode']),
      String(parameters['coreListen']),
      String(parameters['coreSecret']),
      0,
      parameters['coreDebug'] === true ? 1 : 0,
    );
    hilog.info(DOMAIN, TAG, 'core setup result=%{public}s', error);
  }

  /** Creates the vNIC and returns its descriptor. */
  private async createVnic(): Promise<number> {
    const link: connection.LinkAddress = {
      address: { address: TUN_ADDRESS, family: 1 },
      prefixLength: TUN_PREFIX
    };
    const route: connection.RouteInfo = {
      interface: '',
      destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
      gateway: { address: '0.0.0.0', family: 1 },
      hasGateway: false,
      isDefaultRoute: true
    };
    const config: vpnExtension.VpnConfig = {
      addresses: [link],
      routes: [route],
      dnsAddresses: ['1.1.1.1'],
      mtu: TUN_MTU,
      isIPv4Accepted: true
    };
    const conn = vpnExtension.createVpnConnection(this.context);
    this.connection = conn;
    const fd: number = await conn.create(config);
    hilog.info(DOMAIN, TAG, 'vnic created, fd=%{public}d', fd);
    return fd;
  }


  /**
   * Copies a binary out of the package, runs it in a child process and hands
   * it a descriptor, to see whether a core process could own the vNIC that way.
   */
  /**
   * Reads the app's own log files. The app process and this process share the
   * sandbox, and Dart's output does not reach hilog, so the logs on disk are
   * the only place to see what the app did.
   */
  /** Looks for the file the Dart side writes its probe result to. */
  private readDartProbe(filesDir: string): void {
    const name: string = 'ohos_core_probe.txt';
    const directories: string[] = [filesDir];
    try {
      const entries: string[] = fs.listFileSync(filesDir);
      for (const entry of entries) {
        directories.push(`${filesDir}/${entry}`);
      }
    } catch (_) {
    }
    for (const directory of directories) {
      const path: string = `${directory}/${name}`;
      try {
        const handle = fs.openSync(path, fs.OpenMode.READ_ONLY);
        const buffer = new ArrayBuffer(512);
        const read = fs.readSync(handle.fd, buffer);
        fs.closeSync(handle);
        const text = new Uint8Array(buffer, 0, read);
        hilog.info(DOMAIN, TAG, 'dart probe: %{public}s', String.fromCharCode(...text));
        return;
      } catch (_) {
      }
    }
    hilog.info(DOMAIN, TAG, 'dart probe: no probe file found');
  }

  private dumpAppLogs(filesDir: string): void {
    const directories: string[] = [filesDir, `${filesDir}/logs`, `${filesDir}/core`];
    for (const directory of directories) {
      let entries: string[] = [];
      try {
        entries = fs.listFileSync(directory);
      } catch (error) {
        continue;
      }
      hilog.info(DOMAIN, TAG, 'app dir %{public}s entries=%{public}s', directory, entries.join(','));
      for (const entry of entries) {
        if (!entry.endsWith('.log')) {
          continue;
        }
        const path: string = `${directory}/${entry}`;
        try {
          const stat = fs.statSync(path);
          const size: number = stat.size;
          const handle = fs.openSync(path, fs.OpenMode.READ_ONLY);
          const buffer = new ArrayBuffer(1500);
          const read = fs.readSync(handle.fd, buffer, { offset: Math.max(0, size - 1500), length: 1500 });
          fs.closeSync(handle);
          const text = new Uint8Array(buffer, 0, read);
          hilog.info(DOMAIN, TAG, 'app log %{public}s tail=%{public}s', entry, String.fromCharCode(...text));
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'reading %{public}s failed: %{public}s', path, error.message);
        }
      }
    }
  }

  private execProbe(filesDir: string): void {
    this.readDartProbe(filesDir);
    this.dumpAppLogs(filesDir);

    // The app's directories: whether they may be executed from at all.
    try {
      const mounts: string = fs.readTextSync('/proc/mounts');
      const lines: string[] = mounts.split('\n');
      for (const line of lines) {
        if (line.includes('storage') || line.includes('el1') || line.includes('el2')) {
          hilog.info(DOMAIN, TAG, 'exec probe: mount %{public}s', line);
        }
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'exec probe: reading the mounts failed: %{public}s', error.message);
    }
    const target: string = `${filesDir}/ohos-exec-probe`;
    const marker: string = `${filesDir}/exec_probe_marker.txt`;
    const dataFile: string = `${filesDir}/exec_probe_data.txt`;
    try {
      // The raw file lives inside the HAP, so it is read through the resource
      // manager and written out before it can be executed.
      const bytes: Uint8Array = this.context.resourceManager.getRawFileContentSync('ohos-exec-probe');
      const targetFile = fs.openSync(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(targetFile.fd, bytes.buffer);
      fs.closeSync(targetFile);
      hilog.info(DOMAIN, TAG, 'exec probe: wrote %{public}d bytes to %{public}s', bytes.length, target);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'exec probe: writing the binary failed: %{public}s', error.message);
      return;
    }
    // The package's own library directory holds the native libraries, which the
    // loader maps as executable; the app's data directory may not be.
    const libsRoot: string = `${this.context.bundleCodeDir}/libs`;
    let abi: string = 'arm64';
    try {
      const abis: string[] = fs.listFileSync(libsRoot);
      if (abis.length > 0) {
        abi = abis[0];
      }
    } catch (_) {
    }
    const packaged: string = `${libsRoot}/${abi}/libohosprobe.so`;
    hilog.info(DOMAIN, TAG, 'exec probe: packaged binary=%{public}s', packaged);
    try {
      const packagedStatus: number = execWithFd(packaged, -1, marker);
      hilog.info(DOMAIN, TAG, 'exec probe: packaged child status=%{public}d', packagedStatus);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'exec probe: packaged exec failed: %{public}s', error.message);
    }
    try {
      const dataFileHandle = fs.openSync(dataFile, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(dataFileHandle.fd, 'descriptor-payload');
      const status: number = execWithFd(target, dataFileHandle.fd, marker);
      fs.closeSync(dataFileHandle);
      hilog.info(DOMAIN, TAG, 'exec probe: child status=%{public}d', status);
      const markerFile = fs.openSync(marker, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(256);
      const read = fs.readSync(markerFile.fd, buffer);
      fs.closeSync(markerFile);
      const text = new Uint8Array(buffer, 0, read);
      hilog.info(DOMAIN, TAG, 'exec probe: marker=%{public}s', String.fromCharCode(...text));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'exec probe: running the child failed: %{public}s', error.message);
    }
  }

  /**
   * Sends a descriptor to the app process, to test the relay.
   *
   * It sends the descriptor of a UDP socket rather than of a file: a file
   * descriptor comes from the OHOS file manager, and its handling across
   * processes may differ from that of a socket.
   */
  private async sendProbeFd(filesDir: string): Promise<void> {
    const socketName = TUN_SOCKET_NAME;
    let udp: socket.UDPSocket | null = null;
    try {
      udp = socket.constructUDPSocketInstance();
      await udp.bind({ address: '0.0.0.0', port: 0, family: 1 });
      const fd: number = await udp.getSocketFd();
      const sent = await sendTunFd(socketName, fd);
      hilog.info(DOMAIN, TAG, 'relay probe: sent socket fd=%{public}d (result=%{public}d)', fd, sent);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'relay probe failed: %{public}s', error.message);
    } finally {
      if (udp !== null) {
        try {
          udp.close();
        } catch (_) {
        }
      }
    }
  }

  private destroyConnection(): void {
    const conn = this.connection;
    this.connection = null;
    if (conn === null) {
      return;
    }
    conn.destroy().catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'destroying the vpn connection failed: %{public}s', error.message);
    });
  }
}
