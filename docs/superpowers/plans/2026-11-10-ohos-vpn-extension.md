# OHOS VPN 扩展实现计划（fd 注入链）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 OHOS/HarmonyOS 上实现可工作的 VPN 隧道：ETS 建 `VpnExtensionAbility` 拿到 vNIC fd，经新 FFI 导出注入 hiddify-core，复用 Android 生产验证过的 `libbox.OpenInterface → dup → Options.FileDescriptor → tun.New` 链，让 sing-box 在该 fd 上读写 IP 包，真正转发流量。

**Architecture:** `VpnExtensionAbility`（`@ohos.app.ability.VpnExtensionAbility`）→ `vpnExtension.createVpnConnection().create(VpnConfig)` 得 fd → `SetupTun(fd)` C ABI 导出存入 Go 全局 → 构造 `OpenTun()` 返回该 fd 的 `libbox.PlatformInterface` → `hcore.Setup(params, pi)` → `start` 时 `WrapPlatformInterface` 注册 → tun inbound 走 `OpenInterface` → `tun.New(FileDescriptor!=0)`。gRPC 仅作控制面，IP 包走注入的 tun fd。

**Tech Stack:** ETS/ArkTS, OpenHarmony API 26+, DevEco Studio 26.x, OHOS Flutter SDK, Go 1.27 (c-shared / GOOS=linux arm64 + OHOS clang+musl), sing-box/sing-tun (子模块)

**Spec:** docs/superpowers/specs/2026-11-10-ohos-vpn-extension-design.md

## 跨仓库与分支

| 仓库 | 分支 | 改动文件 |
|---|---|---|
| `ShuttleSpace/hiddify-app`（本仓库） | `dev` | `ohos/entry/src/main/module.json5`, `ohos/entry/src/main/ets/**`, `lib/gen/hiddify_core_generated_bindings.dart`, `lib/hiddifycore/core_interface/core_interface_desktop.dart`, `v2/config` OHOS 配置 |
| `ShuttleSpace/hiddify-core` | `ohos-build` | `platform/desktop/custom.go`(新导出), `v2/hcore/`(新 PlatformInterface), `Makefile`(ohos -tags) |
| `hiddify-sing-box`（core 的子模块 fork） | 随 `ohos-build` | `experimental/libbox/service.go` / `tun_name_ohos.go`(新) |

## Global Constraints

- 不改 sing-tun 的 `tun.New` 主体；复用 `Options.FileDescriptor`（`!=0` 即跳过 `/dev/net/tun`）。
- OHOS 特定改动用新增文件 + build tag（`with_ohos`）隔离，不破坏其他平台；`make ohos` 的 `-tags` 追加该 tag。
- gRPC 只做控制面；IP 包绝不走 gRPC。
- fd 必须在 `start()` 之前经 `SetupTun` 设置（`OpenInterface` 发生在 box.New/Inbound.Start 期间）。
- Go `Close()` 会关注入的 fd → 必须 `dup`（复用 libbox `service.go` 现成的 dup 逻辑），ETS 侧不重复 close。
- 地址/路由/DNS 在 ETS 的 `VpnConfig` 配好（注入模式下 Go 侧路由配置全部 no-op）。
- 只用公开 API；不绕过 `MANAGE_VPN`；不同步到上游 `hiddify/hiddify-app`。
- 遵循 AGENTS.md：一个 PR 一个功能，Conventional Commits，不提交生成文件/子模块指针/核心库/真实链接。

## Review Focus

1. **Spike 门禁（最高优先）**：OHOS vNIC fd 是否为 `IFF_NO_PI` 裸 IP 包、能否 `epoll`/`os.NewFile`、`TUNGETIFF` 返回什么——决定 stack 选型，Task 1 不通过不得进入 Task 3+。
2. **fd 所有权**：任何路径都不得让 Go stop 时关掉系统 VPN 句柄；统一 dup。
3. **时序**：`SetupTun(fd)` 必须早于 `start()`；Dart 的 `setup` 在独立 isolate，存 fd 用加锁的进程全局。
4. **"伪 Linux" 副作用**：`C.IsAndroid=false`/`C.IsLinux=true` → 显式关 `auto_redirect`/`auto_detect_interface`、设 `MTU`、禁 `multi_queue`、stack 用 `go`/`gvisor`（**禁 system/mixed**）。
5. **日志**：注册 platform interface 后 `box.go` 默认日志变 `io.Discard`，需另接或依赖 `CrashReport-*.log`。

---

## Phase 0 — Spike 门禁（Task 1，必须先做）

### Task 1: 验证 OHOS vNIC fd 的真实语义（Spike，只读+最小原生实验）

**Files:**
- Read: `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/js/api/@ohos.net.vpnExtension.d.ts`, `@ohos.app.ability.VpnExtensionAbility.d.ts`, `application/VpnExtensionContext.d.ts`
- Create（临时/实验性，验证后可保留为最小 ability）: `ohos/entry/src/main/ets/entryability/VpnExtensionAbility.ets`（最小骨架，仅建档+读一包）
- Modify: `ohos/entry/src/main/module.json5`（最小 `extensionAbilities` 一项，`type: "vpn"`）
- Create: `docs/superpowers/plans/2026-11-10-ohos-vpn-spike-results.md`（记录结论）

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: 明确 vNIC fd 的 (a) 包格式（裸 IP？4 字节 PI 头？）(b) 能否 epoll/os.NewFile (c) `TUNGETIFF` 结果；据此定 stack 选型。

- [ ] **Step 1: 复核 SDK 声明并写出 VpnConfig 最小字段**

确认 `VpnConnection.create(config: VpnConfig): Promise<number>`、`VpnConfig.addresses`（`connection.LinkAddress`）、`routes`（`connection.RouteInfo`）、`dnsAddresses`、`mtu`。记录 `LinkAddress`/`RouteInfo` 的字段（`connection.LinkAddress.address: NetAddress`、`prefixLength`）。

- [ ] **Step 2: module.json5 加最小 vpn extension 声明**

```json5
"extensionAbilities": [
  {
    "name": "VpnExtensionAbility",
    "srcEntry": "./ets/entryability/VpnExtensionAbility.ets",
    "type": "vpn"
  }
]
```
（先不填 icon/label/description 等可选字段，schema 对 `type: vpn` 只要求 `name/srcEntry/type`。）

- [ ] **Step 3: 写最小 VpnExtensionAbility.ets**

```ets
import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import vpnExtension from '@ohos.net.vpnExtension';
import type Want from '@ohos.app.ability.Want';
import connection from '@ohos.net.connection';

export default class MyVpnExtensionAbility extends VpnExtensionAbility {
  async onCreate(want: Want): Promise<void> {
    const cfg: vpnExtension.VpnConfig = {
      addresses: [{ address: { address: '10.0.0.2', family: 1 }, prefixLength: 24 } as connection.LinkAddress],
      mtu: 1500,
      dnsAddresses: ['1.1.1.1'],
    };
    const conn = vpnExtension.createVpnConnection(this.context);
    const fd: number = await conn.create(cfg);   // ← 关键：拿到 vNIC fd
    // 实验：用 native/FFI 直接 read(fd) 一个包，打印前 4 字节
    // 0x45 = IPv4 裸包 / 0x60 = IPv6 裸包；若前 4 字节是 0x0000.. 则可能是 PI 头
  }
  onDestroy(): void { /* destroy() 释放 */ }
}
```
> ETS 层直接 `read(fd)` 需要 NAPI；若 ETS 不便，用一个最小 C 辅助函数（`napi` 或现有 `libhiddify-core.so` 加临时导出）读 fd。此步只为拿到诊断数据。

- [ ] **Step 4: 在 OpenHarmony 模拟器/真机部署，采集诊断**

用 DevEco 部署 HAP（local-debug 签名），触发 VPN 授权，记录：
- `create()` 返回的 fd 是否 > 0；
- 从 fd `read` 到的第一个包前 4 字节；
- `epoll_ctl`/`os.NewFile(fd)` 是否成功；
- `ioctl(fd, TUNGETIFF)` 是否报错、返回什么。

- [ ] **Step 5: 写 Spike 结论并定 stack 选型**

`docs/superpowers/plans/2026-11-10-ohos-vpn-spike-results.md` 写明：
- 裸 IP 包且可 epoll → 用默认 `go` stack，仅需绕开 `getTunnelName`（Task 4 的 build tag）。
- 带 PI 头 → 需自定义 `tun.Tun` 剥头（新增风险任务，先与用户确认）。
- 不可 epoll → 评估 `gvisor` 或阻塞 read 的自定义 Tun。
- 完全不可用 → **停止计划**，回报用户，回退到方案讨论。

- [ ] **Step 6: Commit（Spike 结果 + 最小 ability 骨架）**

```bash
git add docs/superpowers/plans/2026-11-10-ohos-vpn-spike-results.md ohos/entry/src/main/module.json5 ohos/entry/src/main/ets/entryability/VpnExtensionAbility.ets
git commit -m "test(ohos): spike VpnExtensionAbility vNIC fd semantics"
```

**门禁**：Spike 结论为"裸 IP + 可 epoll + 有办法绕开 TUNGETIFF"才进入 Phase 1；否则按 Step 5 分支处理或停下。

---

## Phase 1 — core 侧 fd 注入（Task 2、3，可与 Phase 2 部分并行）

### Task 2: hiddify-core 新增 `SetupTun` C ABI 导出 + `OpenTun` PlatformInterface（`ohos-build` 分支）

**Files:**
- Read: `hiddify-core/platform/desktop/custom.go`（`setup()`/`//export` 风格）、`hiddify-core/v2/hcore/platform_interface.go`（`MobilePlatformInterface`）、`hiddify-core/hiddify-sing-box/experimental/libbox/platform.go`（`PlatformInterface` 接口全集）、`hiddify-core/hiddify-sing-box/experimental/libbox/config.go`（`platformInterfaceStub`）
- Create: `hiddify-core/platform/desktop/ohos_tun.go`（`//export SetupTun`，进程全局 fd + 锁）
- Create: `hiddify-core/v2/hcore/ohos_platform_interface.go`（实现 `libbox.PlatformInterface`，`OpenTun()` 返回全局 fd，其余方法 stub）
- Modify: `hiddify-core/platform/desktop/custom.go`（`setup()` 的 `hcore.Setup(&params, nil)` → 传 OHOS 的 PlatformInterface）

**Interfaces:**
- Consumes: `libbox.PlatformInterface` 接口定义；`hcore.Setup(params, platformInterface)` 签名。
- Produces:
  - `//export SetupTun` `func SetupTun(fd C.int)`（或 `SetTunFd`），把 fd 存入 `static.ohosTunFd`（加锁，跨 isolate 可见）。
  - `OhosPlatformInterface` 实现 `OpenTun(options libbox.TunOptions) (int32, error)` 返回 `int32(static.ohosTunFd)`；其余方法照 `platformInterfaceStub` 返回零值/nil-guard。
  - `setup()` 构造该 interface 传给 `hcore.Setup`。

- [ ] **Step 1: 读全 `libbox.PlatformInterface` 的方法列表，列齐要实现的 stub**

`experimental/libbox/platform.go` 定义了接口；把所有方法签名抄进 `ohos_platform_interface.go`，`OpenTun` 返回全局 fd，其余按 `config.go` stub 处理（尤其 `UsePlatformInterface` 相关由 wrapper 负责，本 interface 不需）。

- [ ] **Step 2: 全局 fd 存储 + SetupTun 导出**

在 `platform/desktop/ohos_tun.go`：
```go
//export SetupTun
func SetupTun(fd C.int) {
    hcore.SetOhosTunFd(int(fd))
}
```
`hcore` 侧提供 `SetOhosTunFd`/`GetOhosTunFd`（`sync.Mutex` 或 `atomic.Int32`）。

- [ ] **Step 3: OhosPlatformInterface.OpenTun 返回全局 fd**

```go
func (p *OhosPlatformInterface) OpenTun(options libbox.TunOptions) (int32, error) {
    fd := hcore.GetOhosTunFd()
    if fd <= 0 { return 0, fmt.Errorf("ohos: tun fd not set (call SetupTun before start)") }
    return int32(fd), nil
}
```

- [ ] **Step 4: setup() 传入该 interface**

`custom.go:97` 附近 `hcore.Setup(&params, nil)` → `hcore.Setup(&params, &hcore.OhosPlatformInterface{})`。
> 注意 `box.go:181` 在 platformInterface != nil 时把默认日志设为 `io.Discard`；如需日志，另接或依赖 `CrashReport-*.log`（记录在 Spike 结论里）。

- [ ] **Step 5: 本地编译校验（不依赖 OHOS 设备）**

```bash
cd hiddify-core
GOFLAGS=-mod=mod GOTOOLCHAIN=local go build ./platform/desktop ./v2/hcore   # 主机 cgo 编译，验证接口实现完整、无未实现方法
```
Expected: 编译通过（若 `//export` 与 C 类型冲突，用 `C.int` 显式）。

- [ ] **Step 6: Commit（core `ohos-build`）**

```bash
git -C hiddify-core add platform/desktop/ohos_tun.go v2/hcore/ohos_platform_interface.go platform/desktop/custom.go
git -C hiddify-core commit -m "feat(ohos): inject VPN tun fd via SetupTun + OpenTun PlatformInterface"
```

### Task 3: 绕开 `getTunnelName` 的 TUNGETIFF（hiddify-sing-box 子模块）

**Files:**
- Read: `hiddify-core/hiddify-sing-box/experimental/libbox/service.go:58-87`, `tun_name_linux.go`, `tun_name_other.go`
- Create: `hiddify-core/hiddify-sing-box/experimental/libbox/tun_name_ohos.go`（`//go:build with_ohos`）
- Modify: `hiddify-core/hiddify-sing-box/experimental/libbox/service.go`（`options.Name` 已给时跳过 `getTunnelName`，或按 fork `//H` 约定改）
- Modify: `hiddify-core/Makefile`（`make ohos` 的 `-tags` 追加 `with_ohos`）

**Interfaces:**
- Consumes: `getTunnelName(fd)` 当前无条件调用；Spike 结论（TUNGETIFF 是否可用）。
- Produces: `with_ohos` tag 下 `getTunnelName` 返回固定名（如 `"tun0"`），不再发 ioctl。

- [ ] **Step 1: 选最小改法**（优先 3 行跳过逻辑，避免动多处 build tag）

在 `service.go` 的 `OpenInterface` 里：若 `options.Name != ""` 则跳过 `getTunnelName`；OHOS 侧在 `VpnConfig` / tun 配置里预置 `Name`。若必须靠 tag，则新增 `tun_name_ohos.go`：
```go
//go:build with_ohos
package libbox
func getTunnelName(fd int32) (string, error) { return "tun0", nil }
```
并把 `tun_name_linux.go` 加 `//go:build linux && !with_ohos`。

- [ ] **Step 2: Makefile ohos target 追加 tag**

`make ohos` 的 `-tags $(TAGS)` 里加入 `with_ohos`（确认 `TAGS` 变量定义处）。

- [ ] **Step 3: 编译验证**

```bash
cd hiddify-core && GOOS=linux GOARCH=arm64 ... go build -tags "... with_ohos" -buildmode=c-shared -o /tmp/libtest.so ./platform/desktop
```
或至少 `go build -tags with_ohos ./hiddify-sing-box/experimental/libbox` 主机编译通过。

- [ ] **Step 4: Commit（子模块 + core 记录新指针仅本地，按 AGENTS.md 不提交子模块指针）**

> 遵循 AGENTS.md：**不提交 hiddify-core 子模块指针变更**。core 侧的 Makefile 提交在 `ohos-build`；子模块改动单独在其仓库提交。

---

## Phase 2 — app 侧接线（Task 4、5、6，依赖 Task 2 的新导出可用）

### Task 4: 重新生成 Dart FFI bindings 暴露 `SetupTun`

**Files:**
- Read: `lib/gen/hiddify_core_generated_bindings.dart`, `ffigen` 配置（`pubspec.yaml` / `*.yaml`）
- Modify: `lib/gen/hiddify_core_generated_bindings.dart`（新增 `SetupTun` 绑定）

**Interfaces:**
- Consumes: core `//export SetupTun(fd: int)` 的 C 签名。
- Produces: Dart `void SetupTun(int fd)`（或 ffigen 生成的实际名字）。

- [ ] **Step 1: 加 SetupTun 绑定**（若本机不便跑 ffigen，按现有 `setup`/`start` 绑定风格手写一条 `lookupFunction`）
- [ ] **Step 2: `dart analyze` 无错**
- [ ] **Step 3: Commit** —— `bindings` 属生成文件，按 AGENTS.md **不提交 `*.g.dart`/生成文件**；此处仅本地使用，或按仓库既有约定处理。`lib/gen/*_generated_bindings.dart` 是否为受控提交文件需先确认 `git ls-files lib/gen/hiddify_core_generated_bindings.dart`。

### Task 5: ETS → Dart → Go 的 fd 通道 + 完整 VpnExtensionAbility

**Files:**
- Modify: `ohos/entry/src/main/ets/entryability/VpnExtensionAbility.ets`（从 Spike 骨架扩成完整：建 vNIC、配地址/路由/DNS、`protect` 底层 socket、`onDestroy` destroy）
- Create: ETS↔Dart 的 MethodChannel 桥（OHOS Flutter plugin 侧，路径按 `ohos/entry/src/main/ets/` 现有 plugin 结构）
- Modify: `lib/hiddifycore/core_interface/core_interface_desktop.dart`（OHOS 分支：在 `setup` 后、`start` 前调用 `SetupTun(fd)`）

**Interfaces:**
- Consumes: Task 2 的 `SetupTun`；Task 4 的 Dart binding；ETS `VpnConnection.create` 的 fd。
- Produces: 连接启动时，fd 从 ETS 经 MethodChannel 到 Dart，再 `SetupTun(fd)` 注入 Go；时序满足"setup 后、start 前"。

- [ ] **Step 1: VpnExtensionAbility 完整实现**
  - `onCreate`: `startVpnExtensionAbility(want)` → `createVpnConnection(this.context)` → `create(VpnConfig{addresses,routes,dnsAddresses,mtu,isIPv4Accepted:true})` → 得 fd；`VpnObserver.onAuthorizationResult` 处理授权。
  - 配好地址/路由/DNS（Go 侧注入模式下不再配）。
  - 通过 MethodChannel 把 `fd`（number）发给 Dart。
  - `onDestroy`: `destroy()`。
- [ ] **Step 2: Dart 侧接 fd**
  - `CoreInterfaceDesktop` OHOS 分支：收到 fd → `bindings.SetupTun(fd)`，**确保先于 `start()`**。
  - 加锁/顺序保证（setup 在独立 isolate，fd 存进程全局）。
- [ ] **Step 3: OHOS 专属 tun 配置**
  - `v2/config`（或 Dart 侧生成的 config）：`auto_redirect=false`、`auto_detect_interface=false`、`mtu=1500`、`multi_queue=false`、`stack=""`(go) 或 `gvisor`，`enable_tun=true` 走 platform 分支。
- [ ] **Step 4: Commit**
```bash
git add ohos/entry/src/main/ets/ lib/hiddifycore/core_interface/core_interface_desktop.dart
git commit -m "feat(ohos): wire VpnExtensionAbility tun fd into hiddify-core"
```

### Task 6: 签名 HAP 并验证流量真正走代理

**Files:**
- Read: `ohos/scripts/fetch-core-lib.sh`（确认带 `SetupTun` 的新 `libhiddify-core.so` 已放入 `ohos/entry/libs/arm64-v8a/`）、`docs/harmonyos.md`（签名命令）
- Modify: `docs/harmonyos.md`（把"VPN 未实现"更新为"fd 注入链已实现 + 已知限制"）

**Interfaces:**
- Consumes: Task 2/3 产出的新 core `.so`；Task 5 的完整接线。
- Produces: 已签名 HAP，流量统计显示上/下行增长，代理生效。

- [ ] **Step 1: 用新 core `.so` 重建**
  - `cd hiddify-core && make ohos`（在 `ohos-build`）→ 得到带 `SetupTun` 的 `bin/lib/hiddify-core.so`。
  - `bash ohos/scripts/fetch-core-lib.sh` 放入 HAP libs 目录（改名 `libhiddify-core.so`）。
  - `flutter build app --release --no-pub`。
- [ ] **Step 2: local-debug 签名**
  - 按 `docs/harmonyos.md` 的 `hap-sign-tool sign-app -mode localSign ...` 命令签 `entry-default-unsigned.hap`。
- [ ] **Step 3: OpenHarmony 设备/模拟器安装并连接**
  - 安装 HAP → 启动 App → 触发 VPN 授权 → 点连接 → hiddify-core `setup/start` → `OpenInterface` 注入 fd → tun 建立。
- [ ] **Step 4: 验证流量走代理**
  - 访问被代理域名；用 hiddify-core 流量统计 / gRPC 查询确认上下行增长。
  - 若失败：按 Review Focus 逐项排查（日志被吞 → 查 `CrashReport-*.log`；fd 被关 → 查 dup；stack → 查 Spike 结论）。
- [ ] **Step 5: 更新文档 + Commit**
```bash
git add docs/harmonyos.md
git commit -m "docs(ohos): document the working tun fd injection and remaining limits"
```

---

## Self-Review

**1. Spec coverage:** 设计文档 7 个实施要点全覆盖——模块声明(Task 1/5)、ETS Ability(Task 1/5)、fd 注入 core(Task 2)、绕开 getTunnelName(Task 3)、fd 通道(Task 4/5)、配置(Task 5 Step 3)、构建签名(Task 6)。Spike 门禁对应「风险与未知数 1」。

**2. Step scan:** 每步单一动作；`//export SetupTun` 用 `C.int`；`OpenTun` 返回 `int32`；fd 时序约束在所有相关任务重复强调。无 TBD。

**3. Type consistency:** 全局统一 `fd: C.int`（FFI）→ `int`（Go 全局）→ `int32`（OpenTun 返回）→ `number`（ETS）→ `int`（Dart）。`VpnConfig` 字段来自 `connection.LinkAddress`/`RouteInfo`。stack 统一 `go`/`gvisor`，禁 system/mixed。

**4. Review Focus 覆盖:** Spike(Task 1)、dup(Global/Task 2 复用 libbox)、时序(Task 5/Global)、伪 Linux(Task 5 Step 3)、日志(Task 2 Step 4 注 + Task 6 Step 4)。

**5. Proportion:** 只给关键代码骨架与精确 `path:line`，不逐行转录；跨仓库/分支表格化。

**6. AGENTS.md 一致:** 不提交生成文件与子模块指针（Task 3 Step 4、Task 4 Step 3 显式标注）；Conventional Commits；不同步上游。

---

**Plan complete and saved to `docs/superpowers/plans/2026-11-10-ohos-vpn-extension.md`.**

**关键门禁提醒**：Task 1（Spike）是全计划的前提。它验证的是「OHOS vNIC fd 能否被 sing-box 的注入链消费」——这是唯一可能无法靠编码绕过、必须先证明的点。建议先只做 Task 1，拿到真机/模拟器诊断数据后再决定是否进入 Phase 1/2。
