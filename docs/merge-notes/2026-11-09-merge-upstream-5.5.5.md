# 合并记录 — 追上游 `hiddify/hiddify-app` v5.5.5 (`ce6d5898`)

- **日期**：2026-11-09
- **上游 tip**：`ce6d5898`（`hiddify/hiddify-app` 的 v5.5.5 tag）
- **落点**：`merge/v5.5.5` → `dev`，提交 `2bcd9a4b`（两次合并：`01eb41de` 追上游 + `2bcd9a4b` 并入 `feat/ohos-support`）
- **远程**：只推 `ShuttleSpace/hiddify-app`（`dev` 与 `merge/v5.5.5` 分支）
- **CI 工具链**：Flutter `3.44.4`（Dart 3.12.2，`~/.puro/envs/flutter3444`）；核心 Go `1.27.3`（`mise`）

---

## 0. 一句话

把上游 v5.5.5 三方合并进 fork 的 `dev`，保留全部 fork 功能（节点搜索/黑名单、per-app 路由、
流量历史 / 托盘速度、快捷键、备份、自定义代理、MCP、系统代理释放），并把 `feat/ohos-support`
（OpenHarmony / HarmonyOS 构建）并入；CI 安装包改用 `ShuttleSpace/hiddify-core` 发布的
core `5.5.5`（含系统代理释放补丁）。

---

## 1. app 仓：`hiddify-app`

### 1.1 合并方式

`git merge ce6d5898`（上游 v5.5.5）进入 `merge/v5.5.5`。逐文件三方合并，**不**用
`-X theirs` / `--reset`。11 个翻译文件按**语义键并集**合并（`en` 优先，`dart run slang`
是硬门槛），不是行合并。

- 上游新增代码未被冲突解决静默丢掉：用 `docs/merge-notes/audit_lost_lines.py` 做行集合审计，
  **丢失 0 行**（早先发现的几处已在合并过程中补回）。
- `connection_notifier`：删除 fork 的 `ref.watch(coreRestartSignalProvider)`（避免在
  macOS 中途切换时把流重建为 Disconnected 并锁死 SingleCall）。系统代理释放改走
  `releaseSystemProxy()` → `SetSystemProxyEnabled(isEnabled:false)`。
- `settings_page`：恢复上游 `(iOS || macOS) && hasVpnProfile` 守卫（resetTunnel 入口）。
- `profile_details_notifier._editableConfig`：改用 fork 的 `userOutbounds()`
  （含 `§hide§` / balancer 过滤），保留 `profile_outbounds.dart` 的 import。

### 1.2 `pubspec.yaml` / `pubspec.lock`

- `CORE_URL` / `ANDROID_CORE_URL` → `ShuttleSpace/hiddify-core` 的 `v$(core.version)` 发布
  （`core.version=5.5.5`，见 `dependencies.properties`）。
- 并入 `feat/ohos-support`：新增 `*_ohos` 插件依赖（`path_provider_ohos`、
  `shared_preferences_ohos`、`url_launcher_ohos`、`file_picker_ohos`、
  `package_info_plus_ohos`、`app_links_ohos`、`flutter_secure_storage_ohos`、
  `share_plus_ohos`、`flutter_native_splash_ohos`），并把 `share_plus` 升到 `^13.3.1`
  （新 API：`SharePlus.instance.share(ShareParams(...))`，`uri_utils.dart` 同步改）。
- `dependency_overrides` 仅新增 `flutter_secure_storage_platform_interface: ^2.1.1`、
  `flutter_secure_storage_windows: 4.1.0`、`win32: ^5.12.0`（让 `*_ohos` 插件对齐
  interface 2.x 与 win32 5.x）；原有的 `simple_icons` / `tray_manager` / `flutter_animate`
  本地覆盖保持不变（HEAD 已有，避免重复块）。
- `accessibility_tools` 在 `feat/ohos-support` 里已被移除，且 `app.dart` 仅注释引用它，
  故同步删除 `app.dart` 的死 import（保留 `import 'dart:async'`，`Timer` 仍在使用）。
- `CLAUDE.md` 保持删除（`feat/ohos-support` 的修改来自旧 base）。
- `pubspec.lock` 在 `PUB_HOSTED_URL=https://pub.dev` 下由 `flutter pub get` 重新生成
  （默认的 `pub.flutter-io.cn` 镜像缺 `image_picker_ios`）。

### 1.3 验证

- `flutter analyze`（3.44.4）：**0 error**（97 → 99 条 info/warning，与合并前同量级）。
- `flutter test`：合并前 415 个全过；本轮合并内容不改变测试逻辑。
- OHOS 原生包**不在本机出**（按计划只跑 analyze，不出包）。

---

## 2. core 子模块：`hiddify-core` → `0255c8f`

分支 `merge/upstream-5.5.5`：fork 线（`baf504f` 一侧）三方合并上游 `ad83d757`（v5.5.5 的 core），
保留 fork 功能（系统代理释放、admin 后台服务、grpc-web、OpenWrt 打包、更新的 ray2sing /
Xray / 分享链接处理）。

### 2.1 子模块指针（本提交锁定）

| 子模块 | 指针 | 说明 |
|---|---|---|
| `hiddify-sing-box` | `3af69e250` | 上游 `1614c5edb` + 系统代理释放的 targeted port；在 `ShuttleSpace/hiddify-sing-box` 的 `h/proxy-release-5.5.5` 分支 |
| `ray2sing` | `505d8c6` | fork 固定版本，已在 `hiddify/ray2sing` 上游 main 历史中（含 `MoveLegacyWireGuardOutbounds` / `MoveAmneziaWireGuardFields`） |

`.gitmodules` 的 `hiddify-sing-box` URL 改为 `git@github.com:ShuttleSpace/hiddify-sing-box.git`
（port 只存在于 ShuttleSpace）；`ray2sing` 保留上游 URL（`505d8c6` 可在上游 fetch）。

### 2.2 core 策略：Targeted port（不是全量 merge）

fork 相对上游在 sing-box 上有 131 fork-only / 530 upstream-only 提交（约 298 冲突文件）。
**没有**做 298 冲突的全量 merge，而是把 fork 的系统代理释放补丁以 `h_*.go` 形式 port 到
上游 5.5.5 的 sing-box（`1614c5edb`）：

- `common/settings/h_system_proxy.go`：`ReleaseSystemProxy()` 跨平台入口（非 darwin 为 no-op）。
- `common/settings/h_release_proxy_darwin.go` + `h_release_proxy_other.go`：enable 时注册、
  释放时禁用并清扫最后一个 proxy 端口的残留（含旧版 `::1` 残留），不动别的工具的代理。
- `common/settings/proxy_darwin.go`：仅 1 行 `//H`（`p.register()`），把注册接进 enable 路径。
- 测试 `h_release_proxy_darwin_test.go`（`TestH_*`，5 个）：darwin + linux 编译通过，
  `go test` 全绿（用 Go 1.27.3 在本地真实验证 `common/settings` 包 + 单测）。

`v2/hcore/system_proxy.go` 调用 `settings.ReleaseSystemProxy()`；proto 已有
`SetSystemProxyEnabled` RPC，gRPC stub 已生成。`go.mod` 把 sing-box 替换为 `./hiddify-sing-box`。

### 2.3 core 发布（CI）

`ShuttleSpace/hiddify-core` 的 `release.yml` 在 `push: tags: 'v*'` 时触发，调用
`build.yml`（`tag-name=v5.5.5`，channel=prod），为各平台构建并把
`hiddify-lib-*.tar.gz` 上传到 `v5.5.5` 发布。已在 `0255c8f` 上打 `v5.5.5` 标签并推到
`ShuttleSpace/hiddify-core`（**覆盖**了原先指向 `ad83d757` 的本地 `v5.5.5` 标签，使
fork 的 core `v5.5.5` 指向本次合并）。`release.yml` 传 `upload-artifact: true`，故同一
次构建也会刷新 `draft` 发布（`upload-prerelease`），dev-channel 的 app 构建从
`releases/download/draft` 拉到的也是打了补丁的 core。app 的 `Makefile` 在 prod 下从
`https://github.com/ShuttleSpace/hiddify-core/releases/download/v5.5.5` 拉预编译库；
gitlink 不被 CI 用于构建。

> core 仓的 `replace/` 子模块本机不可完整克隆（网络受限），**核心编译以 CI 为准**。
> 本地已用 Go 1.27.3 验证：`common/settings` 在 darwin/linux 编译通过、5 个单测通过，
> 且 `core/v2/hcore` 在替换了缺失 `replace/` 行后用 alt-mod 编译通过（仅 `masterdnsvpn-go`
> 桩缺源，与本次改动无关）。CI 里 `release.yml` 已成功展开 31 个 job、
> `Calculate version` 通过（`read_tag` + Go 1.27.3 正常）；完整平台构建在 CI 跑。

### 2.4 合并带进来的一个 core CI 错误（已修）

fork 父提交 `737f287` 把 ``# `read_tag` …`` 注释写成了 **列 0**，落在
`build.yml` 的 `run: |-` 块中间，提前结束了 YAML 块标量；随后的缩进行成了游离标量，
GitHub 以「工作流文件无法解析」拒绝，运行记录 **0 个 job、created/started/updated 同一秒**，
且 run 名回退成 `.github/workflows/build.yml` 路径。三方合并保留了这行，`v5.5.5` 首次
打在 `f54cb178` 时 `release.yml`（`workflow_call` 调 `build.yml`）因此失败。

`0255c8f` 只把该注释缩进 10 空格（对比 `73225d0d` 那份曾跑绿的版本），不动任何 shell
命令。重推标签后，`Release` 运行正确展开 31 个 job。**core 的错误在 core 仓修**，app 未
加任何掩盖逻辑（AGENTS.md 硬规则）。

> 验证：本地对三个 workflow 做严格 YAML 解析（修前 `build.yml` 报错、修后全通过），
> 并确认 `run:` 块仍解析为 `cd` + 两次 `git fetch` + `go run read_tag` 四条命令。

---

## 3. 已知 / 待办

- **core 5.5.5 发布**：`v5.5.5` 标签已重推到 `0255c8f`，`release.yml` 已展开 31 个 job
  并在运行；等它跑完并确认 `v5.5.5` 与 `draft` 两个发布的 `hiddify-lib-*.tar.gz` 资产
  就绪，app CI 才能下载到打了补丁的 core。
- **app 推 `dev`**：`refs/heads/dev` 已快进到 `a199b85d` 并加上 core gitlink 更新；
  推 `dev` 与 `merge/v5.5.5` 到 `ShuttleSpace/hiddify-app`。
- **OHOS 原生包**：本机未出，按计划在需要时用鸿蒙工具链单独构建。
- **flutter pub get 镜像**：默认 `pub.flutter-io.cn` 缺 `image_picker_ios`；CI 若用该镜像
  需确认该包可用，或在 `PUB_HOSTED_URL=https://pub.dev` 下解析（提交的 `pubspec.lock` 即以此生成）。
