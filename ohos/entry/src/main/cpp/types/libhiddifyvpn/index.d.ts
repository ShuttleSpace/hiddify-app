/**
 * N-API surface of libhiddifyvpn.so — the VPN tun fd relay and its probes.
 *
 * The OHOS `type: "vpn"` extension ability runs in its own process and in its
 * own SELinux domain (`vpn_isolate_hap`), so a descriptor cannot be handed to
 * the app process; these helpers work inside one process.
 */

declare const vpnRelay: {
  /**
   * Hands `fd` to whatever process is listening on the socket `socketName`.
   *
   * The socket lives in the Linux abstract namespace: the OHOS app sandbox
   * refuses `bind()` on a filesystem path.
   *
   * @param socketName Socket name; the native side appends the process uid.
   * @param fd Descriptor to transfer; remains valid and owned by the caller.
   * @returns 0 on success, otherwise a negative errno (`-ENOENT` when nothing
   *          is listening yet).
   */
  sendFd: (socketName: string, fd: number) => number;

  /**
   * Waits for one fd to arrive on the socket `socketName` and returns it,
   * already valid in the calling process.
   *
   * The caller owns the returned descriptor and must close it.
   *
   * @param socketName Socket name to bind and listen on.
   * @param timeoutMs How long to wait; the promise rejects with a timeout error.
   */
  receiveFd: (socketName: string, timeoutMs: number) => Promise<number>;

  /**
   * Reads up to `length` bytes from `fd` with a plain syscall, the way
   * hiddify-core uses the descriptor.
   *
   * ArkTS's own fs API refuses a descriptor it did not open itself, so this is
   * what shows that a descriptor is usable by the core.
   *
   * @returns the number of bytes read, or a negative errno.
   */
  readFd: (fd: number, length: number) => number;

  /**
   * Diagnostic: binds and listens on the loopback interface and returns the
   * port, or a negative errno.
   *
   * The VPN extension lives in the `vpn_isolate_hap` SELinux domain; this says
   * whether that domain may listen on loopback, which the app process needs to
   * reach a core running there.
   */
  probeTcpListen: () => number;

  /**
   * Loads libhiddify-core.so into this process and resolves its exports.
   *
   * The core has to run in the VPN extension process: the vNIC descriptor
   * cannot leave that process's SELinux domain.
   *
   * @returns 0 on success, otherwise a negative errno.
   */
  coreLoad: (libraryPath?: string) => number;

  /**
   * Forks, hands `fdNumber` to the child as fd 3 (dup2 clears FD_CLOEXEC, so
   * the descriptor survives the exec) and runs `binaryPath` with HIDDIFY_FD and
   * HIDDIFY_MARKER in its environment.
   *
   * @returns the child's exit status, or a negative errno.
   */
  execWithFd: (binaryPath: string, fdNumber: number, markerPath: string) => number;

  /** 1 when the core library is already mapped in this process. */
  coreIsMapped: () => number;

  /** The last error message of the module, for diagnostics. */
  lastError: () => string;

  /**
   * Hands the vNIC descriptor to the core running in this process. Must be
   * called before the core starts.
   */
  coreSetupTun: (fd: number) => number;

  /**
   * Starts the core's gRPC server. The core's setup blocks until its server is
   * up, so it runs on a worker thread.
   *
   * @returns the error message, empty when it worked.
   */
  coreSetup: (
    baseDir: string,
    workingDir: string,
    tempDir: string,
    mode: number,
    listen: string,
    secret: string,
    statusPort: number,
    debug: number,
  ) => Promise<string>;
};

export default vpnRelay;
