# OHOS VPN 隧道设计：VpnExtensionAbility + 复用 Android 的 tun fd 注入链

> 修订说明（2026-11-10）：初版方案假设"ETS 读 IP 包 → 经 gRPC 转发给 core"且"不改 hiddify-core Go 层"。
> 经对 DevEco 26 SDK 与 hiddify-core / sing-box 子模块的只读侦察，这两点被证伪并修正：
> gRPC 只能传控制面，不能按线速传 IP 包；而 sing-box 已有 Android 生产验证过的 **fd 注入链**可直接复用。
> 用户已授权"改 core 注入 fd"。本版为据此修订后的设计。

## 意图（Why）

OHOS/HarmonyOS 上 hiddify-core 的 gRPC 控制面已跑通（`libhiddify-core.so` 可加载、`setup/start/stop` 等 FFI 接口可用），但仍无法真正转发流量：缺少 `type: "vpn"` 的 extension ability，没有 `VpnExtensionAbility`，核心无法创建 TUN 接口。

本设计的目标是在 OHOS 上实现一个可工作的 VPN 隧道，让 hiddify-core 的配置能落到真正的网络转发上。

## 侦察结论（已核实的事实，非假设）

### OHOS 侧真实 API（DevEco 26 / OpenHarmony SDK）
- **基类**：`VpnExtensionAbility` 来自 `@ohos.app.ability.VpnExtensionAbility`（`@since 11`，`@stagemodelonly`），生命周期 `onCreate(want: Want)` / `onDestroy()`，`context: VpnExtensionContext`。**不是** `@ohos.app.extension.*`。
- **模块声明合法**：`module.json5` 的 `extensionAbilities[].type.enum` 完整白名单里**含 `'vpn'`**（`toolchains/modulecheck/module.json`），注册成立。`ohos.permission.MANAGE_VPN` 已在 `requestPermissions` 声明。
- **建隧道核心**：`vpnExtension`（`@ohos.net.vpnExtension`）：
  - `startVpnExtensionAbility(want)` → `createVpnConnection(context)` 得 `VpnConnection`
  - `VpnConnection.create(VpnConfig): Promise<number>` **返回虚拟网卡（vNIC）的 file descriptor**——这就是 tun 设备，读写它即读写裸 IP 包
  - `VpnConfig` 指定 `addresses` / `routes` / `dnsAddresses` / `mtu` / `isIPv4Accepted` 等，地址与路由必须在这一步配好
  - `VpnConnection.protect(fd)` 保护底层 socket 不走 VPN；`destroy()` 销毁
  - `VpnObserver`（API 26）监听用户授权结果

### hiddify-core / sing-box 侧（子模块 `hiddify-sing-box`，`go.mod replace` 指向本地）
- **tun 无法自建**：OHOS 无 `/dev/net/tun`，`tun.New` 的 Linux 分支会 `open(controlPath)` 失败；core 的 Dart FFI 层无任何 tun/fd/vpn 导出；`vpn`/`tun` 模式只是把 `enable_tun` 写进配置让 sing-box 自建 tun。
- **fd 注入链已存在（Android 生产验证）**：
  - `tun.Options.FileDescriptor`（`replace/sing-tun/tun.go:113`）；`tun_linux.go:54-92` 在 `FileDescriptor != 0` 时直接 `os.NewFile(uintptr(fd), "tun")`，**跳过 `/dev/net/tun`**，且 `Start()`/路由配置/DNS 刷新在注入模式下全部 no-op。
  - `adapter.PlatformInterface.OpenInterface(options, platformOptions) (tun.Tun, error)`（`adapter/platform.go`）；tun inbound（`protocol/tun/inbound.go:112-113,465-475`）在 `usePlatformInterface=true` 时调它而非 `tun.New`。
  - `libbox.platformInterfaceWrapper.OpenInterface`（`experimental/libbox/service.go:58-87`）：`iif.OpenTun(...) → getTunnelName(fd) → dup(fd) → options.FileDescriptor = dupFd → tun.New(*options)`。
  - Android 侧 `VPNService.kt:216-218` 的 `openTun()` 返回 `ParcelFileDescriptor.fd`；`MobilePlatformInterface.OpenTun`（`v2/hcore/platform_interface.go`）转发。
  - `hcore.Setup(params, platformInterface)`（`v2/hcore/grpc_server.go:58-60`）→ `static.globalPlatformInterface` → `start.go:210-216` `WrapPlatformInterface` 注册到 context → `box.go` 取用。
- **唯一 C ABI 入口**：所有 `//export` 都在 `package main` 的 `platform/desktop/*.go`（`custom.go` 的 `setup/start/...`），`make ohos` 就是 `-buildmode=c-shared ./platform/desktop`。`setup()` 目前传 `hcore.Setup(&params, nil)` → 不走 platform 分支。
- **OHOS 无专用 build tag**：`make ohos` 用 `GOOS=linux GOARCH=arm64` + OHOS clang/musl sysroot，`C.IsAndroid=false`、`C.IsLinux=true`。

### 结论
**可行，且不需要改 sing-tun。** 只需让 `hcore.Setup` 收到一个非 nil、`OpenTun()` 返回 OHOS vNIC fd 的 `PlatformInterface`，其余链路全部现成。这比"ETS 读包→gRPC 转发"短得多，且复用成熟路径。

## 目标（Goals）

1. ETS 侧注册 `VpnExtensionAbility`（`type: "vpn"`），用 `vpnExtension` 建立 vNIC，拿到 fd。
2. 把该 fd 经新 FFI 导出注入 hiddify-core，复用 Android 的 `OpenInterface → dup → FileDescriptor → tun.New` 链，让 sing-box 在该 fd 上读写 IP 包。
3. Flutter 侧沿用已有 gRPC 控制面（`CoreInterfaceDesktop`）做启停/配置下发，不引入第二套控制面。
4. 对已有 Android/iOS/macOS/Linux/Windows 平台无破坏性改动（OHOS 特定改动用 build tag / 文件隔离）。
5. 能在 OpenHarmony 模拟器/真机上签名安装并验证流量走代理。

## 非目标（Non-goals）

- 不重写 sing-box 的 tun/stack 实现；不改 `sing-tun` 的 `tun.New` 主逻辑。
- 不在 ETS 侧实现 tun2socks / 用户态 TCP/IP 栈。
- 不支持 iOS/macOS NetworkExtension，不改桌面端 tun 实现。
- 首个版本不处理多 VPN、IPv6 全量、分流规则本地缓存等高级特性。
- 不涉及 AGC 商店发布，仅面向开发者/自签名安装。

## 反目标（Anti-goals）

- **不把 gRPC 当数据面**：gRPC 只用于控制/配置，IP 包一律走注入的 tun fd。
- 不绕过 `ohos.permission.MANAGE_VPN`，不使用未公开私有 API。
- 不改上游 `hiddify/hiddify-app`，改动留在 fork（`ShuttleSpace`）的 `dev` 分支与 core 的 `ohos-build` 分支。

## 约束（Constraints）

1. **跨仓库**：改动分布在 3 处——app（本仓库 `dev`）、hiddify-core（`ohos-build` 分支）、hiddify-sing-box 子模块（仅绕过 `getTunnelName`）。
2. **平台**：OpenHarmony API 26+ / HarmonyOS NEXT，DevEco Studio 26.x，OHOS Flutter SDK。
3. **权限**：`MANAGE_VPN` 是 system_grant/system_basic，商业 HarmonyOS 真机需系统签名；OpenHarmony 设备/模拟器可测。
4. **语言**：`VpnExtensionAbility` 用 ETS/ArkTS；fd 通过 NAPI/FFI 在同一应用进程内传给 Dart→Go（fd 是进程内整数，同进程有效）。
5. **签名**：首个版本 local-debug 自签名，仅装 OpenHarmony 设备/模拟器。

## 方案（Approaches）

### 方案 A：复用 Android 的 tun fd 注入链（选中，用户授权）
ETS 建 `VpnExtensionAbility` 拿 vNIC fd → 新增 FFI 导出 `SetupTun(fd)` 把 fd 存进 Go 全局并构造一个 `OpenTun()` 返回该 fd 的 `PlatformInterface` → `hcore.Setup` 传它 → 复用 libbox `OpenInterface` 链注入 sing-box tun。

- 优点：复用生产验证路径，改动最小；IP 包走原生 tun fd，性能好；不改 sing-tun 主体。
- 缺点：跨 3 仓库；需绕开 `getTunnelName` 的 `TUNGETIFF`；OHOS vNIC fd 的语义需真机验证。
- 风险：见「风险与未知数」。

### 方案 B：ETS 读包 → gRPC 转发给 core
初版设计。**已否决**：gRPC 是控制面，按线速流式传 IP 包不可行，且 core 侧没有接收 IP 包的入口，需重写数据面。

### 方案 C：ETS 侧实现 tun2socks 用户态栈
在 ETS 里做完整 TCP/IP 栈再转给本地 mixed 代理。**已否决**：工作量巨大、易错，且 OHOS fd 仍需注入，无收益。

**决策**：方案 A。

## 已决定的实施要点

1. **模块声明**：`ohos/entry/src/main/module.json5` 的 `extensionAbilities` 增加一项，`type: "vpn"`，`srcEntry` 指向 `VpnExtensionAbility.ets`；`MANAGE_VPN` 权限已存在。
2. **ETS Ability**：新建 `VpnExtensionAbility.ets`，继承 `@ohos.app.ability.VpnExtensionAbility`，`onCreate` 中调 `vpnExtension.startVpnExtensionAbility` → `createVpnConnection(this.context).create(VpnConfig)` 得 fd；`onDestroy` 中 `destroy()`。
3. **fd 注入 core（`ohos-build` 分支，已于 2026-11-11 落地，commit `0566e3e` + 审查修复）**：
   - `platform/desktop/ohos_tun.go` 新增 `//export SetupTun(fd)`，把 fd 存入 `atomic.Int32` 全局。`setup()` **不传** platform interface（保持 nil，桌面/移动零回归）。
   - `v2/hcore/ohos_tun.go` 的 `ohosTunPlatformInterface`（实现 `adapter.PlatformInterface`）：仅当 `GetOhosTunFd()>0` 时在 `start.go` 注册；`OpenInterface` 覆盖为 `dup(fd)→options.FileDescriptor→tun.New`，从而**绕开 libbox wrapper 的 `getTunnelName`(TUNGETIFF)**，**零 fork 改动**。
   - `UsePlatformDefaultInterfaceMonitor=true` + 自带 no-op `ohosInterfaceMonitor`（Start/Close 返回 nil），避开 Linux netlink 与 libbox 的 "platform is nil" monitor；其余 `UsePlatform*` 关闭。
   - `dupOhosTunFd` 用 `F_GETFD` 校验 + `F_DUPFD_CLOEXEC` 复制，`MyInterfaceAddress`/`RegisterMyInterface` 对齐 Android 记账。
   - 重新生成 `lib/gen/hiddify_core_generated_bindings.dart`（ffigen）——Task 4。
   - **一个 Ruling 取代原要点 4**：不改 hiddify-sing-box fork（`service.go` 是上游文件，改它要 `//H`、双语文档、单独分支 + bump 指针）。自定义 `OpenInterface` 便绕开了 `getTunnelName`，无需 `with_ohos` tag。
5. **ETD→Dart→Go 的 fd 通道**：ETS 拿 fd 后经 NAPI/MethodChannel 传给 Dart，Dart 在 `setup` 之后、`start` 之前调用 `SetupTun(fd)`。时序硬约束：**fd 必须在 `start()` 前设置**（`OpenInterface` 发生在 start/box.New 期间）。
6. **配置侧**：OHOS 配置显式关 `auto_redirect` / `auto_detect_interface`，设合理 `MTU`（别用 65535）、`multi_queue=false`，`stack` 用默认 `go` 或 `gvisor`（**不要 system/mixed**）。地址/路由/DNS 全在 ETS 的 `VpnConfig` 里配。
7. **构建与签名**：`flutter build app --release` 打包；`hap-sign-tool` local-debug 签名；OpenHarmony 设备/模拟器验证。

## 风险与未知数（真机验证前无法排除）

1. **裸 IP 包格式 / epoll / `TUNGETIFF` 返回值**（最大风险，Spike 必须验证）：
   - 自定义 `OpenInterface` 只绕开了 **libbox `getTunnelName`** 的 TUNGETIFF；Linux `go` stack 的 `vnetHeaderEnabled()` 仍会发一次 `TUNGETIFF`（失败仅 warn、置 `vnetHeader=false`，非致命），且 `go`/`gvisor` 两种 stack **都依赖 epoll**（`EPOLL_CTL_ADD` / `fdbased`），"换 gvisor 就能躲开 epoll" 不成立。
   - 若 OHOS 返回的不是 `IFF_NO_PI` 裸 IP 包（带 4 字节 PI 头）或不可 epoll，需自定义 `tun.Tun` 剥头或另选 stack。若 `TUNGETIFF` 返回垃圾导致 `IFF_VNET_HDR` 被误判，会给每包加 virtio 头——需在 core 强制 `vnetHeader=false`。
2. **fd 所有权**：`tun_linux.go` `Close()` 会关注入 fd；已用 `F_DUPFD_CLOEXEC` 复制规避（core 侧关的是副本）。ETS 不得重复 close。**fd 生命周期契约**：ETS 每次 `destroy()` 后必须重新 `SetupTun(newFd)` 或 `SetupTun(0)` 清零；`F_GETFD` 校验只能挡已关闭的 fd，挡不住"号码被复用成另一个有效 fd"——这是 app 侧硬约束（core 的 `stopLocked` 不能清零，因为 `restart` 内部走 stop+start 而 VPN 未重建）。
3. **"伪 Linux" 副作用 / 配置是启动前提（不是调优）**：`GOOS=linux` 使 `C.IsAndroid=false`、`C.IsLinux=true`。`mtu`（否则 65535）、`multi_queue=false`、禁 `system`/`mixed` stack、`auto_detect_interface=false` 都是 **Task 5 必须落地的硬前置条件**；`auto_detect_interface=false` 单独并不能阻止 network monitor（已由 no-op monitor 解决）。否则设备上的失败会被误读成"fd 注入链不通"。
4. **protect(fd) 待办（Ruling，本轮未实现）**：`UsePlatformAutoDetectInterfaceControl=false` 关掉了 per-socket `protect` 钩子——OHOS 的 `VpnConnection.protect(fd)` 必须走 ETS，core 是 c-shared 无回调通道；翻回 `true` 只会撞 `MobilePlatformInterface` 的 nil-safe no-op（更隐蔽）。需在 Task 5 明确：靠 `VpnConfig` 排除本应用流量，或预留一个真正调用 `protect(fd)` 的 core 回调。否则 core 自己的出站 socket 可能被吸回 VPN 形成环路。
5. **日志被吞**：注册 platform interface 后 `box.go` 把**默认 stdout/stderr writer** 设为 `io.Discard`；但 `PlatformLogWriter` 仍把日志送进 app 的日志流（需 app 侧订阅）。不是全丢，但 `vnetHeaderEnabled` 的 warning 走这条路。
6. **权限**：`MANAGE_VPN` 是系统级权限，商业机签名受限。

## 建议的起手：最小 Spike（在动全量代码之前）

先不改 app 的 Flutter 侧、不做完整 ETS 交互，只验证「未知数 1」——这是唯一可能无法通过纯编码解决、必须先证明的点：

1. 在 `ohos/entry` 注册最小 `VpnExtensionAbility`，`create(VpnConfig)` 拿到 fd，用 ETS/native 直接 `read` 一个包，打印前 4 字节判断是否为裸 IP（`0x45`/`0x60`）。
2. 确认该 fd 能否被 `epoll`/`os.NewFile` 消费；确认 `TUNGETIFF` 返回什么。
3. 结果决定：走默认 `go` stack / 自定义 `tun.Tun` 剥头 / gvisor，还是此路不通需回退方案。

Spike 通过后，再按「实施要点 1-7」全量落地。

## 留给构建者的工作（What's left）

**已完成（2026-11-11，core `ohos-build`，纯代码部分）**：`SetupTun(fd)` 导出 + 全局 fd + `ohosTunPlatformInterface`（dup→FileDescriptor→tun.New，绕开 getTunnelName，零 fork 改动）+ no-op 默认接口 monitor + MyInterface 记账 + 单元/交叉/OHOS 工具链编译验证。见 commit `0566e3e` 及其审查修复。

**仍待做**：
1. 执行 Spike，记录 OHOS vNIC fd 的语义（裸 IP / epoll / `TUNGETIFF` 返回值与 `IFF_VNET_HDR` 位）。
2. app `dev`：`module.json5` 声明 `type: vpn`、`VpnExtensionAbility.ets`、ETS→Dart→Go 的 fd 通道（含 `SetupTun` Dart binding / ffigen）。
3. Task 5 硬前置：OHOS 专属 tun 配置（mtu、禁 multi_queue、禁 system/mixed stack、关 auto_detect_interface），以及 `protect(fd)` 的 app 侧方案（见风险 4）。
4. fd 生命周期契约落到 ETS：destroy 后重新 `SetupTun` 或清零。
5. 签名 HAP，在 OpenHarmony 设备/模拟器上验证流量走代理。

---

**状态**：设计已按侦察结论修订并经用户授权"改 core 注入 fd"。
**下一步**：把本设计拆成可执行计划（含 Spike 门禁），再开始写代码。Spike 未通过前不进入全量实现。
