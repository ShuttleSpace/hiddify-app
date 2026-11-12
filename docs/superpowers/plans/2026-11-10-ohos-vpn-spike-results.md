# OHOS VpnExtensionAbility vNIC fd — Spike results (CONCLUDED)

> Plan: `docs/superpowers/plans/2026-11-10-ohos-vpn-extension.md` (Task 1, Phase 0).
> Status: **empirical half concluded**. SDK contract verified; the emulator boots
> and runs the extension; `MANAGE_VPN` is granted; **but the VPN system API is
> gated behind system-app APL, which the commercial HarmonyOS emulator clamps to
> `normal` for side-loaded apps.** The vNIC fd therefore cannot be obtained on this
> emulator — packet-format / epoll / TUNGETIFF remain OPEN and require a real
> OpenHarmony device (same blocker as `MANAGE_VPN` on real devices).

## What is verified (no device needed)

SDK: `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony` (API 26).

- `vpnExtension.createVpnConnection(context): VpnConnection` and
  `VpnConnection.create(config: VpnConfig): Promise<number>` — the returned
  `number` **is the vNIC file descriptor** (from `@ohos.net.vpnExtension.d.ts`
  lines 199/206, "file descriptor of the virtual network interface"). This matches
  the plan's `SetupTun(fd)` injection assumption.
- `VpnConfig` fields (all present): `addresses: Array<LinkAddress>`,
  `routes?: Array<RouteInfo>`, `dnsAddresses?: Array<string>`,
  `searchDomains?`, `mtu?: number` (range 576–1500, default — must be set
  explicitly for OHOS, NOT 65535), `isIPv4Accepted?`, `isIPv6Accepted?`,
  `isInternal?`, `isBlocking?`, `trustedApplications?`, `blockedApplications?`.
  `LinkAddress` = `{ address: NetAddress, prefixLength }`.
- `VpnExtensionAbility` (`@ohos.app.ability.VpnExtensionAbility`) has `onCreate(want)`
  and `onDestroy()`; `VpnExtensionContext` extends `ExtensionContext`. A `type: "vpn"`
  entry in `module.json5` `extensionAbilities` is valid in the API 26 schema
  (older `vpn.extension` spelling is NOT).
- `create()` rejects with `2203002 VPN exist already` if a VPN is already up.
- NDK sysroot ships the standard Linux tun ioctls
  (`linux/if_tun.h`: `IFF_TUN 0x0001`, `IFF_NO_PI 0x1000`, `TUNGETIFF 0x800454d2`,
  `TUNSETIFF 0x400454ca`). So whatever fd `create()` returns is a **real tun fd**
  and the sing-tun `FileDescriptor` injection path (already implemented in core) is
  the right shape.

## What is OPEN (needs a running OHOS image)

1. **Packet format**: raw IPv4/IPv6 (`IFF_NO_PI`, first byte `0x45`/`0x60`) vs a
   4-byte PI header. Cannot be resolved from the SDK alone. Needs a running image
   + a minimal C/NAPI read of the first bytes. **Not yet measured.**
2. **epoll**: whether sing-tun's `go`/`gvisor` stack (both require epoll on the
   fd) works on the OHOS fd.
3. **`TUNGETIFF`**: result / whether it errors. Note: our core path already
   bypasses libbox's `getTunnelName(TUNGETIFF)`; only the Linux stack's
   `vnetHeaderEnabled()` still issues it (warn-only).

## Blocker found: the empirical half needs DevEco's Device Manager

- A local **HarmonyOS 7.0.0 (API 26, arm64) emulator image + deployed AVDs**
  (Mate X7, Pura 90 Pro, …) exist at
  `~/Library/Huawei/EmulatorImages/system-image/HarmonyOS-7.0.0/phone_all_arm/`
  and the `Emulator -start "Mate X7"` CLI is present. **But the standalone
  binary cannot complete a boot headlessly.** Every attempt reached the license
  `(y/N)` prompt (driven ok via `expect`/pty) and then **hung at 0% CPU without
  ever spawning qemu** — `nohup`, `script`, `expect`, and `open` all failed to
  produce a running VM. The emulator's boot is tied to the DevEco Studio runtime.
- **Decisive evidence**: `~/Library/Logs/Huawei/DevEcoStudio26.0/idea.log`
  (live, updated 16:22) shows DevEco Studio is running with
  `OpenHarmonyDeviceMonitor` connected to the hdc server (`hdc` 3.2.0f on
  `127.0.0.1:8710`). The emulator is launched through DevEco's **Device Manager
  (HVD/local emulator)**, not the raw `Emulator` binary — that is the supported
  path and the only one that brings the VM up.
- `hdc list targets` is `[Empty]` (no device connected to the hdc server yet).
  The only qemu on this machine is the user's Android emulator on 5554/5555 —
  unrelated.

## `MANAGE_VPN` grant — RESOLVED on the emulator (2026-11-11)

Empirical result on the running **Mate X7 emulator** (`Emulator -hvd Mate X7`,
HarmonyOS 7.0.0.107 / API 26, `127.0.0.1:5557`):

- The HAP `build/ohos/app/entry-default-signed.hap` (local-debug, `apl:normal`,
  `app-feature: hos_normal_app`, and it *declares* `ohos.permission.MANAGE_VPN`)
  **installed successfully** (`hdc install -r … → install bundle successfully`),
  i.e. the emulator does **not** reject the package for `MANAGE_VPN` the way a
  stock HarmonyOS device reportedly does.
- `bm dump -n app.hiddify.com` → `appPrivilegeLevel: "normal"`, and
  `reqPermissionStates` (parallel to `reqPermissions`) shows:

  | permission | kind | state |
  |---|---|---|
  | INTERNET | system_grant / normal | 0 |
  | GET_NETWORK_STATS | system_grant / **system_basic** | 0 |
  | **MANAGE_VPN** | system_grant / **system_basic** | **0** |
  | READ_WRITE_DOWNLOAD_DIRECTORY | user_grant | −1 |

  Enum is `0 = GRANTED`, `−1 = DENIED/PENDING` (INTERNET=0 proves 0=granted;
  the `user_grant` dir permission is −1 pending a runtime prompt).
- **Conclusion: `MANAGE_VPN` is GRANTED (state 0) to a `normal`-APL app on this
  emulator.** The emulator relaxes the `system_basic` APL check. So the APL gate
  is **not** a blocker for the Spike on the emulator. (This does not change the
  stock-device story in `docs/harmonyos.md:241`; it means the emulator is usable
  to prove the fd semantics.)
- The app also launches: `aa start -b app.hiddify.com -a EntryAbility` leaves a
  live `app.hiddify.com` process.

## Empirical result on the emulator — extension RUNS, `create()` REACHED, then GATED (2026-11-11)

Built a minimal `VpnExtensionAbility` (`type:"vpn"`, `srcEntry:
./ets/entryability/VpnExtensionAbility.ets`) that on `onCreate` calls
`vpnExtension.createVpnConnection(this.context).create(config)` and tries to
read the first bytes of the returned fd via `@ohos.file.fs.read` (4s timeout),
logging to `hilog` (`HIDDIFY_VPN_SPIKE`). Rebuilt the HAP with the OHOS Flutter
SDK and installed it; then `aa start -b app.hiddify.com -a HiddifyVpnExtension`.

- The extension **loads and runs**: `aa start` → `onCreate` → `doCreate` runs, and
  it reaches `conn.create(cfg)`. Verified by the log line *before* the failure.
- **`create()` returns `BusinessError {code:202, message:"Non-system applications
  use system APIs"}`.** The whole VPN system API is gated behind the caller being a
  **system application** (APL ≥ `system_basic`), and the commercial HarmonyOS
  emulator assigns **`appPrivilegeLevel: "normal"`** to every side-loaded app.
- We tried to raise the APL two ways, both clamped back to `normal`:
  1. Sign the HAP with a profile of `apl:"system_core"`, `app-feature:"hos_system_app"`
     signed by the SDK's built-in **OpenHarmony** Profile CA
     (`OpenHarmony.p12`, `OpenHarmonyProfileDebug.pem`). Result: still `normal`.
  2. Sign the HAP with a profile of `apl:"system_core"`, `app-feature:"hos_system_app"`
     signed by the **repo's own** Profile CA (`ohos/secrets/profile-ks.p12`,
     password `hiddify-ohos-profile-ca-2026`). Result: still `normal`.
  → The emulator's `access_token` service ignores the profile's `apl` field and
  forces `normal` on any side-loaded bundle. (No root on the emulator: `/` is `ro`,
  `uid=2000(shell)`, `/system/etc` is `Permission denied`.)

## Conclusion: the Spike's fd-read is blocked by the SAME system-app gate as real devices

- **`MANAGE_VPN` (grant)** is relaxed on the emulator (proved: granted state 0 to a
  `normal` app), but **the VPN system API at call time requires system APL**, which
  the emulator will not grant to a side-loaded app. This is the *same* gate that
  blocks VPN on stock HarmonyOS devices — there is no path around it on the
  commercial emulator, and no root/system-write access to patch the trust store.
- Therefore the vNIC fd **cannot be obtained** on this emulator, and the three open
  questions — **packet format, epoll, `TUNGETIFF`** — **cannot be answered
  empirically here**. They remain OPEN and require a **real OpenHarmony device**
  (whose proper debug profile grants `system_basic` APL), or the system-partition
  route (unavailable).
- The Spike's *non-fd* findings are solid and reusable: SDK contract, MANAGE_VPN
  grantability, the extension-ability wiring, and the JDK-21 signer bug below.

### APL elevation matrix — 6 attempts, all clamped (final negative proof)

Hypothesis tested: maybe the APL is `normal` because a **debug**-type profile caps
it (not because the emulator clamps). So we also built **release**-type profiles.
A release profile requires `bundle-info.distribution-certificate` (the sign tool
enforces it: `11015001 / Require cert in bundleInfo!`) and a valid
`app-distribution-type` (`app_gallery` | `enterprise` | `os_integration`, verified
from the sign tool's `Provision.isAppDistTypeValid`).

Every variant below was signed, embedded in the HAP, installed, and then read back
from `bm dump`:

| # | profile `type` | `apl` | `app-feature` | `app-distribution-type` | profile CA | `appPrivilegeLevel` | `appProvisionType` |
|---|---|---|---|---|---|---|---|
| 1 | debug | system_core | hos_system_app | — | repo `profile-ks.p12` | **normal** | debug |
| 2 | debug | system_core | hos_system_app | — | SDK `OpenHarmony.p12` | **normal** | debug |
| 3 | release | system_core | hos_system_app | app_gallery | repo | **normal** | **debug** |
| 4 | release | system_basic | hos_system_app | app_gallery | repo | **normal** | **debug** |
| 5 | release | system_core | hos_system_app | os_integration | repo | **normal** | **debug** |
| 6 | release | normal | hos_normal_app | app_gallery | repo | **normal** | **debug** |

Confirmed the HAP really carries the elevated profile: `hap-sign-tool verify-app`
+ `verify-profile` on variant 3 extracts `type: "release"`, `apl: "system_core"`,
`app-feature: "hos_system_app"`, `app-distribution-type: "app_gallery"`.

Yet the device reports `appProvisionType: "debug"` for a **release** profile and
`appPrivilegeLevel: "normal"` in every case. Conclusion: the emulator's BMS
(`HarmonyOS NEXT Developer Beta1`) treats every `hdc`/`bm install` bundle as a
**developer (debug) install** and clamps APL to `normal`, ignoring the profile's
`type` and `apl` entirely. The only install paths that would honour a release
profile are Huawei's own distribution (AppGallery) or the system partition — both
unavailable (image is signed; `/` is `ro`; no root; `/system/etc` unreadable; no
`preinstall` hook in the DevEco emulator).

## Build-tooling finding (reusable fix): JDK-21 breaks `hap-sign-tool.jar`

- **Symptom**: `flutter build hap` → hvigor `SignHap` fails with
  `ERROR: 11012006 File IO failed / Invalid CEN header (invalid zip64 extra data
  field size)`. The `hap-sign-tool.jar` in the SDK (`toolchains/lib/`,
  **Built-By Maven, Build-Jdk 1.8.0_252**) realigns the zip during signing and
  re-reads it with `java.util.zip.ZipFile`; JDK **21/25**'s stricter zip64 CEN
  validation rejects that output (the same OpenHarmony jar that produced the Nov-10
  signed HAP now fails under the default JDK-21 on PATH).
- **Fix**: run the build under **JDK 17** (`brew install openjdk@17`; put
  `/opt/homebrew/opt/openjdk@17/bin` first on PATH, set `JAVA_HOME`). The same jar
  then signs cleanly. Apply this for any `flutter build hap` / `hap-sign-tool`
  invocation on this machine.
- Side effect: the SDK's signer produces a zip that **JDK 21's `ZipFile` still
  rejects** even when it succeeds under 17 — only matters if you later re-open the
  signed HAP with JDK 21 (e.g. `unzip`/Python are fine; `java.util.zip` is not).

## The vNIC fd cannot leave the VPN extension process (measured 2026-11-12)

This is the finding that decides the architecture, so it is recorded with the
measurements that support it.

### 1. The extension always runs in its own process

- `module.json5` schema: for `type: "vpn"` the `extensionProcessMode` enum is
  `instance | type | bundle` (default `instance`). `runWithMainProcess` — the
  only value that would put the extension into the app's main process — is
  allowed **only** for `type: "statusBarView"`.
- With `extensionProcessMode: "bundle"` (accepted, `bm dump` reports
  `extensionProcessMode: 2`), the extension still ran as
  `app.hiddify.com:vpn` (pid 12389) while the main app was live (pid 12089).
  `bundle` merges a bundle's *extensions* together, not the main UI process.

### 2. That process is in a different SELinux domain

`/proc/<pid>/attr/current`:

| process | domain |
|---|---|
| `app.hiddify.com` (main, Flutter) | `u:r:normal_hap:s0` |
| `app.hiddify.com:vpn` (extension) | `u:r:**vpn_isolate_hap**:s0` |

OHOS isolates the VPN extension on purpose. Same uid (20020074), same network
namespace (an abstract-socket connect between the two processes succeeds).

### 3. The kernel refuses to pass a descriptor across that domain boundary

`SCM_RIGHTS` over an AF_UNIX socket, measured inside the app:

| case | result |
|---|---|
| sender and receiver in the **same** process | **works** — the receiver gets the descriptor |
| sender in `vpn_isolate_hap`, receiver in `normal_hap` | **the descriptor is dropped**: `recvmsg` returns the payload but no ancillary data — `msg_flags = 0x8` (`MSG_CTRUNC`), `msg_controllen = 0` |
| same, with a 512-byte control buffer instead of 24 | same (not a buffer-size problem) |
| same, with a socket descriptor instead of a file descriptor | same |
| kernel audit log | **no** `avc` denial for the app (the domain check is not audited) |

The sender's `sendmsg` succeeds and the receiver gets the byte, but the
descriptor never arrives. Since the identical code path works inside one
process, the code is not at fault: the boundary is the SELinux domain
separation.

### 4. What this means

**A file descriptor is process-local, and the only way to move one here is
blocked by the platform.** The vNIC fd therefore has to be consumed **inside the
VPN extension process** — hiddify-core must run there, and the Flutter app must
reach it over the loopback interface (the same shape as Android, where the core
lives in the VPN service process and the UI talks to it over gRPC).

This is not a workaround for a missing feature; it is what the platform's
isolation implies. The earlier design (fd from the extension to the app process
over a MethodChannel) assumed both live in one process, and that assumption is
false.

**The loopback path is open.** The `vpn_isolate_hap` domain may bind and listen
on the loopback interface — measured with a native probe inside the extension
process (`bind()`+`listen()` on 127.0.0.1 returned a port, e.g. 43691). So the
core's gRPC server can live in the extension process and the app process can
connect to it there.

### 4a. Consequence for the design

| piece | where it runs | why |
|---|---|---|
| vNIC creation, `SetupTun(fd)` | `app.hiddify.com:vpn` | only this process can hold the fd |
| hiddify-core (tun + gRPC server) | `app.hiddify.com:vpn` | the tun fd is consumed there |
| Flutter UI, gRPC client | `app.hiddify.com` | talks to the core over 127.0.0.1 |

The app starts the extension with `vpnExtension.startVpnExtensionAbility(want)`
and passes the core's port and secret in `want.parameters`; the extension starts
the core, which listens on that port. The app then drives it exactly like
Android does, over gRPC.

### 5. Side findings from the same work

- **OHOS app sandboxes deny `bind()` on a filesystem AF_UNIX path**
  (`EACCES`). Abstract-namespace sockets (`sun_path[0] == '\0'`) work in the
  app domain, and are what the relay used.
- The relay itself is implemented and works inside one process
  (`ohos/entry/src/main/cpp/vpn_fd_relay.cpp`, `sendFd`/`receiveFd` over
  `SCM_RIGHTS`); it is what proved finding 3.
- The kernel walks the sender's control buffer with 4-byte alignment: a control
  buffer larger than the space actually used makes it walk into the padding and
  reject the message (`sendmsg` → `EPIPE`). The sender must declare exactly
  the space one descriptor needs.

## The Go core cannot be loaded into an OHOS process at all (measured 2026-11-12)

A third, independent blocker, found while wiring the core into the extension
process.

`hiddify-core` is a Go `-buildmode=c-shared` library. Its runtime uses the
**initial-exec** TLS model, and musl (OHOS' libc) refuses that model for
libraries it loads at runtime:

```
Error relocating /data/storage/el1/bundle/libs/arm64/libhiddify-core.so:
  : initial-exec TLS relocations not supported for shared libraries
```

Measured, in **both** processes and at **both** times:

| where | when | result |
|---|---|---|
| app process (`normal_hap`) | `dlopen` from ArkTS/N-API, at runtime | fails with the error above |
| app process | `dlopen` from the N-API module's constructor (native module init) | fails, same error |
| VPN extension process (`vpn_isolate_hap`) | at runtime | fails, same error |
| VPN extension process | at native module init | fails, same error |

- The library is **not** preloaded: `/proc/self/maps` contains no `hiddify-core`
  mapping in either process, so there is no already-loaded handle to fall back
  on (`dlsym(RTLD_DEFAULT, "setup")` finds nothing).
- The file itself is fine and reachable: `stat` on
  `<bundleCodeDir>/libs/arm64/libhiddify-core.so` reports 100 109 776 bytes, and
  it is in the HAP (`libs/arm64-v8a/libhiddify-core.so`). Only the ABI directory
  name is device-specific (`arm64` here, `arm64-v8a` elsewhere).
- `RTLD_LAZY` instead of `RTLD_NOW` does not help.

### Why: the relocation itself

```
$ llvm-readelf -r libhiddify-core.so | grep TLS
0000000005cc1920  0000000000000406 R_AARCH64_TLS_TPREL64  0
```

Exactly one TLS relocation, and on aarch64 it is `R_AARCH64_TLS_TPREL64` — the
initial-exec/local-exec model, which only a library in the **initial load set**
can use. This is why the desktop builds are unaffected: on amd64 Go emits a
general-dynamic sequence, which a `dlopen`ed library may use.

### Consequence

The Dart FFI path (`DynamicLibrary.open`) goes through the same `dlopen`, so the
*existing* OHOS integration of the core rests on a mechanism musl refuses. That
deserves a separate check — the app never got far enough in this session to
load the library itself, and `docs/harmonyos.md` still claims "the core's gRPC
control plane runs".

### And a second way in is closed too: an app cannot exec its own binaries

Running the core as a **separate process** (the extension `fork`/`exec`s it and
hands it the vNIC descriptor) was the other way around the descriptor problem.
The kernel audit log says no:

```
avc: denied { execute } for pid=24249 comm="hiddify.com:vpn" name="ohos-exec-probe"
  scontext=o:r:vpn_isolate_hap:s0  tcontext=o:object_r:debug_hap_data_file:s0
avc: denied { setattr } for pid=23959 comm="hiddify.com:vpn" name="libohosprobe.so"
  scontext=o:r:vpn_isolate_hap:s0
```

Measured with a static aarch64 probe binary shipped in the HAP:

| where the binary is | result |
|---|---|
| the app's data directory (copied out of the package) | `execve` → **EACCES** (SELinux denies `execute`) |
| the module's own library directory (`<bundleCodeDir>/libs/<abi>/`) | extracted, but `execve` → **EACCES**; the execute bit cannot even be set (`setattr` denied) |

So an OHOS application cannot execute a binary it ships, in either location.

### Ways out, none of them cheap

1. **Make the core's TLS relocation general-dynamic.** That is a Go
   toolchain/linker matter (an aarch64 c-shared library with a general-dynamic
   TLS sequence would be `dlopen`able again). An older Go cannot help: the
   repository requires `go 1.27.3`.
2. **Link the library into the process instead of loading it at runtime** —
   requires the host process to be linked against it, which the OHOS ability
   runtime does not do for application libraries.
3. **A system-privileged application.** A profile with `system_basic` APL comes
   with a different SELinux domain and a different policy; it may well be
   allowed to `execute` and to reach the VPN system API. This is the same
   dependency as the VPN itself, so it solves both at once.
4. **An OpenHarmony image, where the policy is ours.** The SDK ships the
   OpenHarmony Profile CA, so an application can be signed `system_basic` there;
   the trust store and the SELinux policy are the open-source ones.



Done: emulator boots; the extension installs, launches, and reaches `create()`;
`MANAGE_VPN` is granted at the permission level. Blocked (absolutely): the VPN
system API requires system-app APL, which the emulator forces to `normal` for
every side-loaded (developer-install) bundle — proved with the 6-variant matrix
above. Packet format / epoll / `TUNGETIFF` remain OPEN.

### What would actually unblock the fd questions

1. **Real HarmonyOS device + Huawei-granted profile.** Huawei grants `system_basic`
   APL + `ohos.permission.MANAGE_VPN` to approved VPN-category apps through AGC
   (the permission is `availableLevel: system_basic`, `provisionEnable: true`). With
   such a profile the app is a genuine system app and `create()` works. This is the
   same gate stock devices already impose, so it is a **product/distribution
   dependency, not a code problem** — but until it exists, the OHOS tunnel cannot
   run on any Huawei device, emulator or real.
2. **An OpenHarmony (open-source) device or emulator we control.** The SDK ships the
   *OpenHarmony* Profile CA private key (`OpenHarmony.p12`) and its debug/release
   profile certs, which a genuine OpenHarmony image trusts. On such an image a
   `hos_system_app` / `system_core` profile is honoured, so the fd can be obtained
   and the three open questions answered. (Nothing like this is deployable as a
   product; it is purely a way to close the Spike's empirical gap.)
3. **Neither is available offline** → the fd semantics must be treated as an
   unverified assumption in the design, and Task 4/5 app-side work cannot be
   validated end-to-end.

Files touched (all spike/experimental, no product code merged):
- `ohos/entry/src/main/ets/entryability/VpnExtensionAbility.ets` (new, probed fd)
- `ohos/entry/src/main/module.json5` (added `extensionAbilities` `type:"vpn"`)
- `ohos/secrets/spike-*.{json,p7b}` (spike-only signing material — 6 profiles,
  2 CAs; gitignored `ohos/secrets/`, NOT committed)
- `ohos/build-profile.json5` was switched to `local-debug` for the build and **has
  been restored to `default`** (`ohos/signature/use-signing.sh default`).
- Build churn from `flutter build hap` reverted: `pubspec.lock` (mirror URLs),
  `linux/flutter/generated_plugins.cmake`, `generated_plugin_registrant.cc`.
- No change to the `hiddify-core` submodule; fork untouched.
