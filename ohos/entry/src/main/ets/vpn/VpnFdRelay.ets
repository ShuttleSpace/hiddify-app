/**
 * VPN tun fd relay — ArkTS side.
 *
 * The `type: "vpn"` extension ability runs in its own process
 * (`<bundle>:vpn`), while hiddify-core runs in the Flutter process. A file
 * descriptor is a per-process integer, so the vNIC fd from
 * `VpnConnection.create()` has to be handed over SCM_RIGHTS; ArkTS cannot call
 * sendmsg/recvmsg itself, hence libhiddifyvpn.so.
 *
 * The two sides meet on a Linux **abstract-namespace** AF_UNIX socket: the OHOS
 * app sandbox refuses `bind()` on a filesystem path (EACCES), and an abstract
 * name needs no writable directory. The native side appends the process uid to
 * the name, so these are names, not paths.
 *
 * Order matters: the receiving side must be listening **before** the extension
 * calls create(), otherwise sendFd finds no listener.
 */
import relay from 'libhiddifyvpn.so';

/** Socket name of the real tun fd relay. */
export const TUN_SOCKET_NAME: string = 'tun';

/** Socket name of the relay self test (kept apart so it cannot disturb a live relay). */
export const TUN_SELF_TEST_SOCKET_NAME: string = 'selftest';

/**
 * Default receive timeout. The extension has to start, be authorised by the
 * user, and create the vNIC, so this is generous on purpose.
 */
export const TUN_FD_TIMEOUT_MS: number = 30000;

/**
 * Sends `fd` to the listener at `socketName`, retrying briefly while the peer
 * has not bound the socket yet.
 *
 * @returns 0 on success, otherwise the last negative errno from the native side.
 */
export async function sendTunFd(socketName: string, fd: number, attempts: number = 50): Promise<number> {
  let last: number = -1;
  for (let i = 0; i < attempts; i++) {
    last = relay.sendFd(socketName, fd);
    if (last === 0) {
      return 0;
    }
    // -ENOENT / -ECONNREFUSED: no listener yet, keep trying.
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 100));
  }
  return last;
}

/** Waits for one fd and resolves with it (valid in the calling process). */
export function receiveTunFd(socketName: string, timeoutMs: number = TUN_FD_TIMEOUT_MS): Promise<number> {
  return relay.receiveFd(socketName, timeoutMs);
}

/**
 * Reads from a relayed descriptor with a plain syscall.
 *
 * @returns the number of bytes read, or a negative errno.
 */
export function readRelayedFd(fd: number, length: number = 64): number {
  return relay.readFd(fd, length);
}
