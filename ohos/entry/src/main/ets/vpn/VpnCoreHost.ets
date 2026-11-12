/**
 * Hosting hiddify-core in the VPN extension process.
 *
 * The VPN extension runs in its own SELinux domain (`vpn_isolate_hap`) and the
 * kernel refuses to pass the vNIC descriptor out of it, so the core has to run
 * where the descriptor is: in this process. The app process then drives it
 * over the loopback interface, the same way Android drives the core in its VPN
 * service process.
 */
import relay from 'libhiddifyvpn.so';
import fs from '@ohos.file.fs';

/**
 * The path of the core library inside the module: <bundleCodeDir>/libs/<abi>/.
 * The ABI directory is named after the device ("arm64", "arm64-v8a", ...), so
 * it is read rather than assumed.
 */
export function coreLibraryPath(bundleCodeDir: string): string {
  const libsRoot: string = `${bundleCodeDir}/libs`;
  let abi: string = 'arm64-v8a';
  try {
    const abis: string[] = fs.listFileSync(libsRoot);
    if (abis.length > 0) {
      abi = abis[0];
    }
  } catch (_) {
  }
  return `${libsRoot}/${abi}/libhiddify-core.so`;
}

/**
 * Loads libhiddify-core.so and resolves its exports. 0 on success.
 *
 * `libraryPath` is the module's own library directory: the extension process
 * does not have the app's library directory on its loader path.
 */
export function loadCore(libraryPath: string): number {
  return relay.coreLoad(libraryPath);
}

/**
 * Runs `binaryPath` in a child process with `fdNumber` handed to it as fd 3,
 * so a descriptor survives the exec.
 *
 * @returns the child's exit status, or a negative errno.
 */
export function execWithFd(binaryPath: string, fdNumber: number, markerPath: string): number {
  return relay.execWithFd(binaryPath, fdNumber, markerPath);
}

/** 1 when the core library is already mapped in this process. */
export function coreIsMapped(): number {
  return relay.coreIsMapped();
}

/** The last error message of the native module, for diagnostics. */
export function lastError(): string {
  return relay.lastError();
}

/**
 * Hands the vNIC descriptor to the core in this process. Must be called before
 * the core starts, and after the vNIC exists.
 */
export function setupTun(fd: number): number {
  return relay.coreSetupTun(fd);
}

/**
 * Starts the core's gRPC server.
 *
 * The core's setup blocks until it has loaded its data and started its server,
 * so it runs on a worker thread; the promise resolves with the error message,
 * empty when it worked.
 */
export function setupCore(
  baseDir: string,
  workingDir: string,
  tempDir: string,
  mode: number,
  listen: string,
  secret: string,
  statusPort: number,
  debug: number,
): Promise<string> {
  return relay.coreSetup(baseDir, workingDir, tempDir, mode, listen, secret, statusPort, debug);
}
