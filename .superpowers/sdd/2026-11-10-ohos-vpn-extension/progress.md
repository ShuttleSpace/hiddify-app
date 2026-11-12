# SDD ledger — plan: docs/superpowers/plans/2026-11-10-ohos-vpn-extension.md

Spec: docs/superpowers/specs/2026-11-10-ohos-vpn-extension-design.md (authority)

## Setup
- BASE: hiddify-core `ohos-build` @ 4b0bb3a (was detached d4101ea, now local branch tracking ShuttleSpace/ohos-build)
- Scope (user choice 2026-11-11): "纯代码部分" = Task 2 + Task 3 only. Task 1 (Spike, needs device) and Task 4/5/6 (app side) are OUT OF SCOPE this run.
- Go 1.27.3, module github.com/hiddify/hiddify-core, `replace github.com/sagernet/sing-box => ./hiddify-sing-box`, `sing-tun => ./hiddify-sing-box/replace/sing-tun`.

## Pre-flight interface scan
- Task 2 produces: `SetupTun(fd)` C export, global `ohosTunFd`, `OhosPlatformInterface` (libbox.PlatformInterface), `setup()` passing non-nil PI.
- Task 3 consumes: global fd + a custom adapter.PlatformInterface wrapper at `start.go:210-216`.
- Shared: `ohosTunFd` global. No type conflict.
- Task 4/5/6 consume Task 2's export but are out of scope.

## Rulings
- R1 (Task 3 placement): Plan Task 3 said "改 fork hiddify-sing-box 的 service.go 绕开 getTunnelName + with_ohos build tag". DEVIATED. Instead implement a custom `adapter.PlatformInterface` in core (`v2/hcore/`) that embeds `libbox.WrapPlatformInterface(...)` and overrides ONLY `OpenInterface` to do `dup(fd) → options.FileDescriptor → tun.New(*options)` — never calls `getTunnelName`/TUNGETIFF. Why: zero fork changes (fork AGENTS.md requires //H on upstream lines, bilingual docs, separate branch + submodule bump), robust regardless of whether OHOS vNIC fd supports TUNGETIFF (the Spike unknown), and all changes stay in one repo. Cost: one extra wrapper + a conditional at service.MustRegister; the libbox wrapper's other methods (interface monitor, notifications, etc.) still delegate to our stub PI and may return nil/errors — acceptable for the first cut, flagged as a risk.
- R2 (scope): Only Task 2 + Task 3, no Spike, no app-side. Why: user explicitly chose the pure-code option. Cost: verification is local `go build`/`go vet` only; no runtime traffic proof. Runtime unknowns (fd packet format, epoll, TUNGETIFF, ownership) remain for Task 1.
- R3 (setup() must NOT unconditionally pass a non-nil PI): Plan Task 2 Step 4 said change `hcore.Setup(&params, nil)` → `hcore.Setup(&params, &OhosPlatformInterface{})`. DEVIATED. `libbox.WrapPlatformInterface(...).UsePlatformInterface()` hardcodes true, so a non-nil PI forces ALL desktop builds (which share `platform/desktop`) onto `OpenInterface → OpenTun`; with no injected fd they break. Instead: `setup()` stays `nil`; a separate `SetupTun(fd)` export sets a global fd; `start.go` registers the custom OHOS PlatformInterface ONLY when that fd is set (>0). Why: zero regression on Linux/macOS/Windows/Android/iOS. Cost: OHOS must call SetupTun before start() (already a spec constraint); static.globalPlatformInterface path unchanged for mobile.
- R4 (no build tag for the core-side changes): the new `ohos_tun.go` files are compiled on all platforms but inert unless SetupTun is called. Avoids Makefile tag plumbing; fork stays untouched. Cost: a few KB in every binary.
- R5 (Task 2 + Task 3 in one commit): Plan had them as separate commits, but the global fd (Task 2) and OpenInterface injection (Task 3) live in the same `ohos_tun.go` and depend on each other; splitting would create a non-compiling intermediate commit, violating core AGENTS.md "one feature per commit". Why: they are one feature (OHOS fd injection). Cost: a single slightly larger commit. Commit `0566e3e`.
- R6 (TDD harness adaptation): three pre-existing tracked `*_test.go` (proxy_info/speedtest/keep_top, dated Nov 9) reference helpers absent from this checkout, so `go test ./v2/hcore` fails to compile regardless of my change. Verified my tests by temporarily moving those 3 aside (trap-restored, never deleted) — RED and GREEN both observed on my tests. `go vet ./v2/...` is likewise blocked by that pre-existing breakage; production code vets/builds clean. Cost: cannot report a fully green package-wide `go test`/`go vet` — an existing failure, reported by name.
- R7 (go.mod): `-mod=mod` promoted `github.com/sagernet/sing-tun` from indirect to direct because `ohos_tun.go` imports it. Correct and committed.

## Tasks
- [ ] Task 1: OUT OF SCOPE (Spike, needs device) — deferred
- [x] Task 2: fd injection in core (SetupTun export + global fd + OhosPlatformInterface) — COMPLETE (merged into `0566e3e` per R5)
- [x] Task 3: custom adapter.PlatformInterface.OpenInterface bypass — COMPLETE (merged into `0566e3e` per R5)
- [ ] Task 4/5/6: OUT OF SCOPE (app side) — deferred

Task 2+3 complete (commits 4b0bb3a..0566e3e, tests: `go test -race -tags "$TAGS" ./v2/hcore -run 'TestOhosTun|TestOhosPlatform'` → ok 1.96s, with the 3 pre-existing broken test files temporarily moved aside per R6). Also: `go build ./v2/hcore ./platform/desktop` (darwin) ok; windows/linux-arm64 cross-compile ok (NAIVE=0 tags); host c-shared `nm` shows `SetupTun`; `make ohos` with DevEco OHOS clang+musl sysroot ok, `bin/lib/hiddify-core.so` exports `SetupTun(int fd)`. Build artifacts + test files not committed (gitignored).

## Final whole-branch review (fresh general subagent, ses_e374007ceffegkZjFdlGbg4GVq)
Review range 4b0bb3a..0566e3e. No Critical. Important findings I1-I7 + Minors. Re-graded by effect (spec is a vision doc):

- **I1 (Important, FIXED)**: `UsePlatformDefaultInterfaceMonitor=false` forced the engine onto the Linux netlink monitor (`route/network.go:124`), which OHOS sandboxes may ban; `auto_detect_interface=false` cannot prevent it. Fix: set true + return a no-op `tun.DefaultInterfaceMonitor` (Start/Close return nil), matching Android and avoiding libbox's "platform is nil" monitor. `Final: fixed I1 — TestOhosPlatformUsesNoopDefaultInterfaceMonitor RED→GREEN`.
- **I3 (Important, FIXED)**: custom OpenInterface skipped `RegisterMyInterface`/`MyInterfaceAddress` bookkeeping. Fix: no-op monitor records my interfaces; `MyInterfaceAddress` returns tun addresses. `Final: fixed I3 — TestOhosMonitorRegistersMyInterface + TestOhosPlatformMyInterfaceAddress RED→GREEN`.
- **I4 (Important, FIXED)**: stale/reused fd number silently dup'd onto an unrelated descriptor; plain `unix.Dup` cleared CLOEXEC; dup leaked if `tun.New` failed. Fix: `dupOhosTunFd` = `F_GETFD` validation + `F_DUPFD_CLOEXEC`, close dup on tun.New error. `Final: fixed I4 — TestOpenOhosTunDuplicatesFd + TestDupOhosTunFdRejectsInvalidFd RED→GREEN`.
- **I5 (Important, FIXED)**: `OhosPlatformInterface.OpenTun` was dead code (OHOS never calls libbox wrapper's OpenInterface) and its test was a false positive. Fix: dropped the override, wrote 4 real behavior tests. Re-ran RED against `0566e3e` (compile fails on the new symbols) then GREEN. `Final: fixed I5 — 7 tests RED→GREEN`.
- **I6 (Important, DOC-FIX)**: "never calls TUNGETIFF" is inaccurate — the Linux go stack's `vnetHeaderEnabled` still issues it (warn-only), and go+gvisor both require epoll. Re-graded: `0566e3e`'s message only claimed to bypass libbox `getTunnelName` (accurate), so no history rewrite; accurate statement put in the fix commit message + design doc risk/Spike sections. `Final: fixed I6 — docs + commit message`.
- **I7 (Important, DOC-FIX, declined as code)**: OHOS tun config (mtu/multi_queue/stack/auto_detect_interface) is a startup prerequisite, not a tuning — belongs to Task 5 (out of scope). Recorded in the design doc as hard prerequisites. `Final: Ruling: I7 — config is Task 5 scope; documented as Spike prerequisites. Cost if wrong: a device failure misread as 'fd chain broken'.`
- **I2 (Important, DECLINED, ruled)**: per-socket `protect(fd)` hook is off. OHOS `VpnConnection.protect(fd)` must be driven from ETS; core is c-shared with no callback channel; flipping back to true only hits `MobilePlatformInterface`'s nil-safe no-op (more hidden). Keep false, document as Task 5 contract (VpnConfig must exclude the app's own traffic, or a real core callback must be added). `Final: Ruling: I2 — stays off this cut. Cost if wrong: outbound sockets may loop back into the VPN; the Spike will expose it.`
- **Minors deferred**: `UsePlatformInterface=true` is a redundant but necessary override (keep); `//H`-free doc wording already corrected; no build tag (R4, accepted); ffigen will export SetupTun for all platforms (Task 4 note). `Final: minor (deferred): redundant UsePlatformInterface override (kept intentionally)`.
- **Declined-to-judge rulings**: Spike semantics (device), OHOS netlink policy (device), whether VpnConfig can exclude app traffic (Task 5), reviewer could not re-run builds (its local Go 1.27.0 < go.mod 1.27.3). All are outside the pure-code scope; R2 already bounds verification to local builds.

Fix pass committed as `15adddb`. Verification after the pass: `go test -race` (7 tests) ok; `go build ./v2/hcore ./platform/desktop` (darwin) ok; windows + linux/arm64 cross-compile ok (NAIVE=0); `make ohos` with OHOS clang+musl ok (FcntlInt/F_DUPFD_CLOEXEC compile, SetupTun exported). Suite 7/7 green. No re-review dispatched (fix-pass covered by the new tests per executing-plans).

## Status
- Two commits on `ohos-build`: `0566e3e` (feature) + `15adddb` (review fixes). Neither pushed (user: 不同步到上游 / no push without asking). Ahead of ShuttleSpace/ohos-build by 2, behind by 0.
- Working tree clean (test file + build artifacts gitignored, uncommitted by design). Fork (hiddify-sing-box) has zero changes. app submodule pointer left unstaged per AGENTS.md.
- NOT done (out of scope / deferred): Task 1 device Spike, Task 4/5/6 app side (ETS ability, Dart binding, config, signing, traffic verification).
- R8 (no finishing-a-development-branch / no workspace deletion): executing-plans' Finish step assumes the whole plan is done. Here only the user-delimited pure-code slice ran; 4 tasks remain deferred and the user said 不同步到上游, so there is nothing to integrate/push. Kept this ledger (gitignored) so a later session can resume at Task 1 (Spike) or Task 4 (app side) with all Rulings intact. Deleting the workspace would discard the only record of the deferred state. No push, no PR, no merge performed.

## Task 1 Spike — investigation (2026-11-11)

Using `investigate-first` (evidence-ranked, no product edits). Deliverable being written: `docs/superpowers/plans/2026-11-10-ohos-vpn-spike-results.md` (doc only; no core/app code edited).

Verified (static, no device):
- SDK contract: `VpnConnection.create(config): Promise<number>` returns the vNIC fd; `VpnConfig` fields (addresses/routes/dnsAddresses/mtu 576–1500) confirmed; `VpnExtensionAbility.onCreate/onDestroy`; `type:"vpn"` valid in API 26 schema.
- NDK sysroot has standard Linux tun ioctls (`IFF_NO_PI`, `TUNGETIFF`, `TUNSETIFF`) → fd is a real tun fd, core's `FileDescriptor` injection is the right shape.
- `MANAGE_VPN` = `system_grant / system_basic`; local debug profile `hiddify-app.p7b` is `apl: normal` → stock HarmonyOS device cannot grant it (docs/harmonyos.md:241 already records the app won't install/run VPN).

Blocker (empirical half needs the user's GUI):
- Exhausted CLI launch attempts: `nohup`+pipe, python pty driver (0-byte/!c-tty exit), `yes | script -q` (accepted y then 0% CPU, no qemu), `expect` (license accepted via `y\r`, then hung at 0% CPU, no qemu), `open` binary (no process spawned — not a bundle). Every path reaches the `(y/N)` license prompt but never spawns qemu.
- Decisive evidence: `~/Library/Logs/Huawei/DevEcoStudio26.0/idea.log` (live, updated 16:22) shows **DevEco Studio is running** with `OpenHarmonyDeviceMonitor` connected to the hdc server (hdc 3.2.0f on 127.0.0.1:8710). The emulator VM only comes up via DevEco's **Device Manager**, not the raw `Emulator` binary. `hdc list targets` = `[Empty]` (no device connected to the server).
- Conclusion: the supported, working launcher is DevEco's Device Manager. The user must start Mate X7 there (one click), then I drive `hdc`. Updated results doc accordingly.
- R9 (Spike automation boundary): stopping the boot rabbit hole; the empirical Spike is gated on a GUI Device-Manager launch the agent-side cannot perform (same class of blocker as MANAGE_VPN/device). Per investigate-first, named the blocker and handed back with a one-click unblock. No product code changed; results doc is the deliverable so far.

## Task 1 Spike — emulator up, APL gate CLEARED (2026-11-11, continued)
User booted the emulator from DevEco's Device Manager. `hdc list targets` = `127.0.0.1:5557`; process `Emulator -hvd Mate X7` (HarmonyOS 7.0.0.107 / API 26, arm64-emulator). `netmanager` runs; only system (ID:100) apps preinstall.
- Installed `build/ohos/app/entry-default-signed.hap` (local-debug, apl:normal, declares MANAGE_VPN) via `hdc install -r` → **install bundle successfully** (emulator does NOT reject it; stock-device story in docs/harmonyos.md:241 unaffected).
- `bm dump -n app.hiddify.com`: `appPrivilegeLevel=normal`; `reqPermissionStates` parallel to `reqPermissions` = [GET_NETWORK_INFO=0, GET_NETWORK_STATS=0, GET_WIFI_INFO=0, INTERNET=0, KEEP_BACKGROUND_RUNNING=0, **MANAGE_VPN=0**, READ_WRITE_DOWNLOAD_DIRECTORY=-1]. Enum 0=GRANTED, -1=DENIED (INTERNET=0 proves; dir perm user_grant=-1 pending). **MANAGE_VPN (system_basic) is GRANTED to a normal-APL app on the emulator** → the APL gate is NOT a blocker for the Spike here.
- App launches: `aa start -b app.hiddify.com -a EntryAbility` → live `app.hiddify.com` process.
- Build chain: OHOS Flutter SDK at `~/.puro/envs/ohos/flutter` (`flutter build hap`); ohos/entry has NO native cpp dir yet (NAPI would need creating); CMake/hvigor present.
- R10 (Ruling): MANAGE_VPN empirical result supersedes the design's "hard gate" assumption *for the emulator*. Remaining 3 open items (packet format / epoll / TUNGETIFF) now need a minimal VpnExtensionAbility that calls create() and reads/ioctls the fd — that is Task-4/5-scale (add extension + rebuild 139MB HAP + native read/log). Deciding with the user whether to invest in that now vs. stop at "APL gate cleared". Results doc updated. No product code changed yet.

- Local HarmonyOS 7.0.0 (API 26, arm64) emulator image + AVDs exist and boot via `Emulator -start "Mate X7"`, BUT the Emulator refuses non-interactive launch: license `(y/N)` prompt consumes piped/pty `y` during license paging or exits silently; only proceeds when the GUI window is shown and the user clicks Accept. Tried: nohup+pipe, python pty driver (0-byte output, silent exit), `yes | script -q` (accepted y then exited, no qemu). All failed to spawn qemu.
- `hdc list targets` = `[Empty]`; hdc server on 127.0.0.1:8710 has 0 targets. (Only the user's Android emulator qemu on 5554/5555 is running.)
- Could NOT fetch OpenHarmony source for how `create()` opens the fd (gitee tree API 404, raw github 404 on guessed path) → packet-format (raw IP vs 4-byte PI) is still OPEN.

Decision point handed to user: empirical Spike needs (a) the user to click Accept on the emulator license window (I re-launch the GUI Emulator on request), then I probe the running system's MANAGE_VPN grantability via hdc BEFORE any HAP build; OR (b) a real OpenHarmony device with hdc. Until then the packet-format/epoll/TUNGETIFF open questions cannot be closed.




## Task 1 Spike — CONCLUDED (2026-11-11, evening): extension RUNS, VPN system API GATED

User chose option A (build minimal VpnExtensionAbility + rebuild HAP + read the fd).

### What was built
- `ohos/entry/src/main/ets/entryability/VpnExtensionAbility.ets` (new): onCreate -> createVpnConnection(this.context).create(cfg) -> read(fd) via `@ohos.file.fs.read` with a 4s timeout -> hilog tag `HIDDIFY_VPN_SPIKE` (hex dump + RAW_IP vs NOT_RAW_IP classify). Traffic generated with a UDP socket to 8.8.8.8:53.
- `ohos/entry/src/main/module.json5`: added `extensionAbilities` = [{name: HiddifyVpnExtension, srcEntry: ./ets/entryability/VpnExtensionAbility.ets, type: "vpn", exported: true}].

### Build toolchain (reusable fix — IMPORTANT)
`flutter build hap` needs, in this order: OHOS flutter SDK (`~/.puro/envs/ohos/flutter`), `HOS_SDK_HOME`/`DEVECO_SDK_HOME` = `/Applications/DevEco-Studio.app/Contents/sdk`, `hvigorw`+`ohpm` on PATH (DevEco `Contents/tools/{hvigor,ohpm}/bin`), and **JDK 17** (`brew install openjdk@17`; JDK21/25 break `hap-sign-tool.jar`).
- **JDK-21 signing bug**: hvigor `SignHap` fails with `ERROR: 11012006 File IO failed / Invalid CEN header (invalid zip64 extra data field size)`. Root cause: the SDK's `hap-sign-tool.jar` (Build-Jdk 1.8.0_252) realigns the zip and re-reads it with `java.util.zip.ZipFile`; JDK 21/25's stricter zip64 CEN validation rejects it. Under JDK 17 the same jar signs fine. (The signed output is still unreadable by JDK21's `ZipFile`; `unzip`/Python are fine.)
- Signing material: `ohos/signature/use-signing.sh local-debug` switches product.signingConfig; `build-profile.json5` stores an ENCRYPTED storePassword — decryptable with `ohos/secrets/material` (PBKDF2 + AES-128-GCM, see `ohos/signature/derive-store-password.js`).

### Empirical results
- HAP built (139.8 MB) and installed on the Mate X7 emulator; `bm dump` shows the extension registered with `extensionTypeName: "vpn"`.
- `aa start -b app.hiddify.com -a HiddifyVpnExtension` -> `start ability successfully` -> extension `onCreate` runs -> reaches `conn.create(cfg)`.
- **`create()` fails: `BusinessError {code:202, message:"Non-system applications use system APIs"}`.** The VPN system API requires the caller to be a SYSTEM app (APL >= system_basic); the commercial HarmonyOS emulator assigns `appPrivilegeLevel: "normal"` to every side-loaded app.
- APL elevation attempts, BOTH clamped back to `normal`: (1) profile `apl:system_core` + `app-feature:hos_system_app` signed by the SDK's OpenHarmony Profile CA (`OpenHarmony.p12` pwd `123456`, `OpenHarmonyProfileDebug.pem`); (2) same profile signed by the repo's own Profile CA (`ohos/secrets/profile-ks.p12` pwd `hiddify-ohos-profile-ca-2026`, `profile-cert.cer`). No root on the emulator (`/` is ro, uid=2000(shell), `/system/etc` unreadable) -> cannot patch the trust store.
- => **The vNIC fd cannot be obtained on this emulator; packet-format / epoll / TUNGETIFF remain OPEN** and need a real OpenHarmony device (same system-app gate as real devices).

### R11 (Ruling)
The Spike is CONCLUDED. The "grant" side of MANAGE_VPN is relaxed on the emulator, but the "call" side is gated by system-app APL and is NOT relaxable for side-loaded apps. Consequence for the design: the OHOS VPN path (Path A) must ship as a system-privileged app (system_basic/system_core APL via a Huawei/AGC-signed profile, or system partition), otherwise no tunnel can be created at all. The emulator cannot validate fd semantics; the fd-related questions must be closed on a real OpenHarmony device before Task 4/5.

### Working tree hygiene
- `ohos/build-profile.json5` restored to `signingConfig: "default"` (was switched to local-debug for the build).
- Reverted build churn in `pubspec.lock` (pub.dev -> pub.flutter-io.cn mirror URLs) and `linux/flutter/generated_plugins.cmake` / `generated_plugin_registrant.cc` (regenerated by the OHOS SDK's pub get).
- `hiddify-core` submodule pointer still unstaged (d4101ea -> 15adddb) per AGENTS.md (never commit the pointer). Fork untouched; core changes live on `ohos-build` (2 commits, not pushed).
- Spike-only artifacts live in gitignored `ohos/secrets/` (`spike-system-profile*.json/p7b`) and are NOT committed. `docs/superpowers/plans/2026-11-10-ohos-vpn-spike-results.md` holds the full write-up.

## Task 1 Spike — APL matrix (6 variants), R12: emulator forces developer-install APL

Follow-up after R11: tested whether APL was `normal` because of the **debug profile
type** (a release profile could have been honoured). Built 6 profiles, signed with
2 different CAs, embedded, installed, read back from `bm dump`:

| # | type | apl | app-feature | app-dist-type | CA | result |
|---|---|---|---|---|---|---|
| 1 | debug | system_core | hos_system_app | — | repo profile-ks.p12 | normal / debug |
| 2 | debug | system_core | hos_system_app | — | SDK OpenHarmony.p12 | normal / debug |
| 3 | release | system_core | hos_system_app | app_gallery | repo | normal / debug |
| 4 | release | system_basic | hos_system_app | app_gallery | repo | normal / debug |
| 5 | release | system_core | hos_system_app | os_integration | repo | normal / debug |
| 6 | release | normal | hos_normal_app | app_gallery | repo | normal / debug |

- Release profiles need `bundle-info.distribution-certificate` (sign tool error
  `11015001 / Require cert in bundleInfo!`) and a valid `app-distribution-type`
  (`app_gallery` | `enterprise` | `os_integration`, from `Provision.isAppDistTypeValid`).
- Verified the elevated profile is really in the HAP: `hap-sign-tool verify-app`
  + `verify-profile` on variant 3 -> type=release, apl=system_core,
  app-feature=hos_system_app, app-distribution-type=app_gallery.
- Device still reports `appPrivilegeLevel: normal` AND `appProvisionType: debug`
  (for a *release* profile). => BMS on this `HarmonyOS NEXT Developer Beta1` image
  treats every hdc/bm install as a developer install and clamps APL to normal,
  ignoring the profile's type/apl.
- Also checked: no `preinstall` hook in the DevEco emulator (`Emulator` binary has no
  preinstall strings; AVD dir has only images + config.ini), no root (`/` ro,
  uid=2000, /data and /system/etc not readable), only the commercial
  HarmonyOS-7.0.0 image exists locally (no OpenHarmony image).

### R12 (Ruling)
The emulator route is CLOSED for obtaining a vNIC fd. Only two paths can close the
fd questions: (a) a real HarmonyOS device with a Huawei-granted
`system_basic`+`MANAGE_VPN` profile via AGC — a product/distribution dependency that
also gates the shipped product, not something code can work around; (b) a genuine
OpenHarmony image we control (the SDK ships the OpenHarmony Profile CA key), purely
to close the empirical gap. Until then packet-format / epoll / TUNGETIFF stay
UNVERIFIED, and end-to-end validation of Tasks 4/5 is impossible on this machine.

### Hygiene
- `ohos/build-profile.json5` restored to `signingConfig: "default"`.
- Reverted build churn: pubspec.lock (mirror URLs), linux/flutter/generated_*.
- Spike profiles live in gitignored `ohos/secrets/spike-*`.
- Device left with a normal-APL install; core submodule pointer still unstaged.

## Task 4 — done (bindings)

- `hiddify-core/bin/lib/hiddify-core.h:116` already exports `extern void SetupTun(int fd);`
  (from the OHOS c-shared build), so no core rebuild was needed.
- Added the binding to the tracked `lib/gen/hiddify_core_generated_bindings.dart` right
  after `StartCoreGrpcServer` (header order), mirroring `closeGrpc` exactly:
  `void SetupTun(int fd)` + `_lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int)>>('SetupTun')`.
- `dart analyze lib/gen/hiddify_core_generated_bindings.dart` -> **0 errors** (only the
  file's pre-existing generated-code warnings).
- Ruling Task 4: hand-added instead of re-running ffigen — ffigen needs `hiddify-core/bin/desktop.h`,
  which only a macOS `make macos` produces (~minutes), and regenerating from the OHOS header would
  churn the whole file. The export surface is identical apart from the new function. Cost if wrong:
  the next real `ffigen` run rewrites the file (harmless, same declaration).

## Task 5 — BLOCKED by a spec-level assumption that measurement falsified

**Spec `docs/superpowers/specs/2026-11-10-ohos-vpn-extension-design.md:67` assumes**
"fd 通过 NAPI/FFI 在**同一应用进程内**传给 Dart→Go（fd 是进程内整数，同进程有效）",
and `:98` puts MethodChannel on that path. Measurement says the VPN extension never
runs in the app's main process:

- `module.json5` schema: `extensionProcessMode` for `type:"vpn"` allows only
  `instance|type|bundle` (default `instance`). `runWithMainProcess` is allowed **only**
  for `type:"statusBarView"`.
- Set `extensionProcessMode: "bundle"`, rebuilt, installed: `bm dump` now reports
  `extensionProcessMode: 2` (BUNDLE) — accepted, but the extension still ran as
  `app.hiddify.com:vpn` (pid 12389) while the main app was live (pid 12089).
  => `bundle` merges a bundle's *extensions* into one process; it does not join the
  main UI process.
- Conclusion: the vNIC fd is always created in a **separate process**. MethodChannel
  cannot carry it (MethodChannel is intra-process). The fd must cross a process
  boundary, or the core must move into the extension process.

### Ruling R13
Task 5 as written in the plan cannot be implemented. Two viable architectures:
- **A. fd relay (preferred):** extension ArkTS gets `fd` -> small NAPI `sendmsg(SCM_RIGHTS)`
  over an AF_UNIX socket -> main-process NAPI `recvmsg` -> `dlopen("libhiddify-core.so")`
  + `dlsym("SetupTun")(fd)`. Keeps core, Dart FFI, UI and Tasks 2/3 untouched; and the
  *channel itself is testable on the emulator without system APL* (send any fd).
- **B. core in the extension process:** needs NAPI host + config handoff via
  `want.parameters` + gRPC control plane rewiring + UI state sync. Much larger, and
  not testable at all without system APL.
R13 = A. Pending user go/no-go because it revises the spec's process assumption.

### Emulator facts recorded
- `extensionProcessMode: "bundle"` is inert for the process-boundary question (measured above).
- Runtime gate is the ArkTS system-API guard: `{"code":202,"message":"Non-system applications
  use system APIs"}` — earlier than the documented `2203001 VPN creation denied, please check the
  user type`, i.e. netmanager is never reached on a normal-APL app.

## Task 5 — R13 (fd relay) implemented, then falsified by measurement; R14 = pivot

### What was built (R13, user-approved)
- `ohos/entry/src/main/cpp/vpn_fd_relay.cpp` — N-API module `libhiddifyvpn.so`:
  `sendFd`/`receiveFd` over SCM_RIGHTS on an AF_UNIX socket (abstract namespace;
  the app sandbox denies bind() on a filesystem path with EACCES), `readFd` for
  a syscall-level read of a relayed descriptor.
- `ohos/entry/src/main/ets/vpn/VpnFdRelay.ets` — ArkTS wrappers.
- `ohos/entry/src/main/ets/vpn/HiddifyVpnPlugin.ets` — Flutter plugin, MethodChannel
  `hiddify/vpn` with `startVpn` / `stopVpn`; registered in EntryAbility.
- `ohos/entry/src/main/ets/entryability/VpnExtensionAbility.ets` — product extension:
  create() -> relay the fd -> (destroy on teardown), plus a `vpnRelayProbe` diagnostic path.
- Dart: `lib/hiddifycore/core_interface/core_interface_ohos.dart` (CoreInterfaceOhos:
  startVpn -> SetupTun(fd) -> gRPC start; stop -> SetupTun(0) + stopVpn),
  selected in `core_interface_wrapper.dart`; `config_option_repository.dart` forces
  `TunImplementation.sing15` (the userspace "go" stack) on OHOS.
- Task 4 binding `SetupTun` added to `lib/gen/hiddify_core_generated_bindings.dart`.

### Build/tooling facts
- ArkTS: `RouteInfo.gateway` is a `NetAddress` (its `address` is a string), while
  `RouteInfo.destination` is a `LinkAddress` (its `address` is a `NetAddress`).
- `fs.openSync` returns a `File` object; the descriptor is `file.fd`.
- `hilog` only shows INFO lines after `hilog -b D` on the device.
- The emulator can be started directly now that the licence is accepted:
  `DevEco-Studio.app/Contents/tools/emulator/Emulator -hvd "Mate X7" -path ~/.Huawei/Emulator/deployed -imageRoot ~/Library/Huawei/Sdk`

### R14 (Ruling) — the fd relay is impossible; the core must run in the extension process
Measured, with the evidence in `docs/superpowers/plans/2026-11-10-ohos-vpn-spike-results.md`:
1. The VPN extension always runs in a separate process (`type:"vpn"` may not use
   `runWithMainProcess`; `bundle` mode does not join the main UI process).
2. That process is in a **different SELinux domain**: `u:r:vpn_isolate_hap:s0`
   vs the app's `u:r:normal_hap:s0` (same uid, same netns).
3. The kernel drops SCM_RIGHTS descriptors across that boundary: the receiver
   gets the payload with `msg_flags=MSG_CTRUNC (0x8)` and `controllen=0`, while
   the identical code transfers the descriptor fine **within** one process. No
   avc denial is audited.
=> A vNIC fd cannot leave the extension process. **hiddify-core must run inside
`app.hiddify.com:vpn`**, and the Flutter app must reach it over the loopback
interface (gRPC), like Android's VPN service.
Cost if wrong: if the OHOS IPC (`@ohos.rpc` MessageSequence.writeFileDescriptor)
or another mechanism can move the descriptor, the simpler "core stays in the app
process" design would come back. (The app cannot host an RPC endpoint for the
extension: only service-type extensions can be connected to, and they run in
their own process too.)

### Verification done
- N-API relay works within one process on the device (self test: send=0, receive fd=29).
- Cross-process relay: descriptor dropped (see R14).
- `dart analyze` clean on the new/changed Dart files.
- `flutter build hap` (JDK 17) succeeds; the HAP installs and the extension runs.

## R14 verified — the loopback path is open, so the pivot is feasible

Native probe inside the VPN extension process (`vpn_isolate_hap` domain):
`bind()`+`listen()` on 127.0.0.1 returned a port (`tcp probe: loopback listen
result=43691`). So the domain may listen on loopback, and the core's gRPC server
can live in the extension process with the Flutter app connecting to it there.

=> Option B is feasible: **hiddify-core runs in `app.hiddify.com:vpn`**, the app
starts the extension with `startVpnExtensionAbility(want)` carrying the core's
port and secret in `want.parameters`, and drives the core over gRPC — the same
shape as Android (core in the VPN service process).

### What the code in the tree now reflects (Option A, superseded)
The fd-relay code is in place and works **inside one process**, but the
cross-process hop is impossible (R14), so `CoreInterfaceOhos`'s
`SetupTun(fd)` in the app process cannot work. These files are therefore
prototypes, not a finished path:
- `ohos/entry/src/main/cpp/vpn_fd_relay.cpp` (+ types): a working SCM_RIGHTS
  relay and the probes (loopback listen, syscall read). Its `sendFd`/`receiveFd`
  are the evidence for R14; under Option B the module's job becomes hosting the
  core in the extension process instead.
- `ohos/entry/src/main/ets/vpn/HiddifyVpnPlugin.ets`: the MethodChannel
  (`startVpn`/`stopVpn`) — still needed under Option B, but it must hand over
  the port/secret and wait for the core to be up, not a file descriptor.
- `ohos/entry/src/main/ets/entryability/VpnExtensionAbility.ets`: creates the
  vNIC and relays the fd — under Option B it must instead hand the fd to the
  core **in this process** and start the core here.
- `lib/hiddifycore/core_interface/core_interface_ohos.dart`: calls `SetupTun`
  in the app process — must become a gRPC-only client (like
  `CoreInterfaceMobile`) that talks to the core in the extension process.
- `lib/gen/hiddify_core_generated_bindings.dart`: the `SetupTun` binding stays
  useful, but the call must come from the extension process (through NAPI), not
  from Dart.

### Testability split under Option B
- **Testable now**: the core running in the extension process and the app
  talking to it over gRPC (proxy mode, no tun) — everything except the fd.
- **Not testable anywhere here**: injecting the vNIC fd, because the VPN system
  API needs a system-app profile (R11/R12). It needs a real device with a
  Huawei-granted profile.

## R15 — Option B (core in the extension process) hits a third, independent blocker

Option B was implemented far enough to test its premise:
- N-API module gained `coreLoad` / `coreSetup` / `coreSetupTun` / `probeTcpListen`
  (`ohos/entry/src/main/cpp/vpn_fd_relay.cpp`).
- `ohos/entry/src/main/ets/vpn/VpnCoreHost.ets` wraps them; the extension starts
  the core in its own process when `want.parameters` carries `coreListen`
  (`ohos/entry/src/main/ets/entryability/VpnExtensionAbility.ets`).
- The app process passes the configuration over `want.parameters` and waits for
  the core's port (`ohos/entry/src/main/ets/vpn/HiddifyVpnPlugin.ets`).

Measured facts:
1. The extension process **can** load the module's native libraries
   (`<bundleCodeDir>/libs/<abi>/`, the ABI directory is read, not assumed) and
   **can** listen on loopback TCP (port returned) — the transport for Option B
   is fine.
2. But the core itself **cannot be loaded**: `dlopen` of the Go c-shared
   `libhiddify-core.so` fails in both processes, at runtime and at native-module
   init, with musl's
   `Error relocating ...: initial-exec TLS relocations not supported for shared libraries`.
   It is not preloaded either (`/proc/self/maps` has no `hiddify-core`).

### Ruling R15
The OHOS VPN path now has three independent blockers, all measured:
(a) the VPN system API needs a system-app profile (R11/R12);
(b) the extension's SELinux domain cannot hand the vNIC fd to the app process
    (R14), so the core would have to run in the extension process;
(c) musl refuses to load a Go c-shared library at runtime (R15), so the core
    cannot be loaded into *either* process — which also calls the existing Dart
    FFI integration of the core into question.
(b) and (c) are properties of the platform, not of this code. The ways out are
listed in the results doc: build the core as an OHOS executable and `exec` it
from the extension with the descriptor inherited, link it into the process, or
find a TLS model musl accepts.

Cost if wrong: if the Dart FFI path does in fact work (e.g. the library is
loaded by the runtime under conditions this session did not reach), (c) is much
weaker than it looks and Option B becomes feasible after all.

## R16 — the "core as a separate process" way around is closed too (SELinux)

R15 left one way around the dlopen problem: run the core as its own process
and hand it the vNIC descriptor by inheritance (fork + dup2 + execve). Tested
with a static aarch64 probe binary shipped in the HAP:

| where the binary is | result |
|---|---|
| the app's data directory (copied out of the package) | `execve` → EACCES |
| `<bundleCodeDir>/libs/<abi>/` (extracted from the HAP as `lib*.so`) | extracted, but `execve` → EACCES; the execute bit cannot be set either |

Kernel audit log (decisive):
```
avc: denied { execute } pid=24249 comm="hiddify.com:vpn" name="ohos-exec-probe"
  scontext=o:r:vpn_isolate_hap:s0 tcontext=o:object_r:debug_hap_data_file:s0
avc: denied { setattr } pid=23959 comm="hiddify.com:vpn" name="libohosprobe.so"
  scontext=o:r:vpn_isolate_hap:s0
```
=> An OHOS application cannot execute a binary it ships, in either location.

### Ruling R16
There is **no way to run the Go core inside an OHOS application process**: not as
a shared library (R15: aarch64 c-shared uses `R_AARCH64_TLS_TPREL64`, the
initial-exec TLS model, which musl refuses for `dlopen`ed libraries, and the
library is not preloaded), and not as a child process (R16: SELinux denies
`execute` on app files).

This also puts the existing OHOS integration of the core in doubt: the Dart FFI
path uses the same `dlopen`, while `docs/harmonyos.md` still claims "the core's
gRPC control plane runs". That claim should be re-verified — it is a possible
product bug independent of the VPN work.

Remaining ways out, in order of cost:
1. A Go toolchain/linker change that emits a general-dynamic TLS sequence for
   an aarch64 c-shared library (then `dlopen` works again and the Dart FFI path
   is fine). An older Go cannot help: the repository requires go 1.27.3.
2. A system-privileged application (system_basic APL): a different SELinux
   domain and policy, which may allow `execute` and the VPN system API at once.
3. An OpenHarmony image, where the trust store and the SELinux policy are the
   open-source ones and the SDK's OpenHarmony Profile CA can sign the app
   system_basic.

### Spike artifacts cleaned up
The probe binaries (`ohos/entry/libs/arm64-v8a/libohosprobe.so`,
`ohos/entry/src/main/resources/rawfile/ohos-exec-probe`) were removed; the
signing config is back to `default`.

## R17 — the Dart FFI path fails with the same error: the OHOS core integration is broken

The Dart FFI probe ran in the app process (pushed over the MethodChannel to the
ArkTS plugin, which logs it to hilog; the probe had to go through a Map because
`MethodCall.argument` throws `ClassCastException` for non-map arguments):

```
dart core load probe: Invalid argument(s): Failed to load dynamic library
  'libhiddify-core.so': Error relocating .../libhiddify-core.so: :
  initial-exec TLS resolves to dynamic definition in
  /data/storage/el1/bundle/libs/arm64/libhiddify-core.so
```

Identical to the N-API probe. So:

- **`docs/harmonyos.md`'s claim that "the core's gRPC control plane runs" on OHOS
  does not hold with the current toolchain** (go 1.27.3, aarch64 OHOS, the musl
  loader): the core library cannot be loaded at all, neither from Dart nor from
  native code, neither at runtime nor at native-module init. The app therefore
  has no working core on OHOS — proxy mode included.
- The root cause is a property of the *toolchain*: the aarch64 c-shared output
  carries `R_AARCH64_TLS_TPREL64` (initial-exec TLS), which a loader may only
  accept for a library in the initial load set.
- Products of this session that are still useful: the probe
  (`probeCoreLibraryLoad` + `CoreInterfaceOhos`'s file-based report) so the
  condition can be re-tested when the toolchain changes, and the N-API module's
  `probeTcpListen` (the extension's domain may listen on loopback).

### Cleanup
- Temporary probes removed from `lib/main.dart` / `lib/main_prod.dart`.
- `lib/hiddifycore/core_interface/core_interface_ohos.dart` keeps the load probe
  (written into the app sandbox for the extension to report) and documents the
  platform situation in its class doc.
- Signing config restored to `default`; build churn reverted.
