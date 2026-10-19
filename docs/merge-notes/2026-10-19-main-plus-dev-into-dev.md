# Merge note — 上游 main + fork app 层 → `dev`

- **日期**：2026-10-19
- **落点提交**：`97735b13`（合并）/ `b7ba44d6`（CI 修复）
- **远程**：只推 `ShuttleSpace/hiddify-app`。上游 `hiddify/hiddify-app` 未动，fork 的 `main` 未动。
- **验证状态**：Android release APK 装机通过（能过闪屏、首页/设置可渲染、tab 可切、手动添加面板可开可切 tab）。

---

## 0. 一句话结论

`dev` 现在 = **上游 `main` 的代码** + **fork 的 app 层功能** + **本轮设备验证后修掉的坑**，
树与真机上验过的 `main-plus-dev`（`f1e26b3c`）**逐字节一致**（`git diff main-plus-dev dev` 为空）。

---

## 1. 拓扑

```
上游 main  f26aadb3 ─┐
                     ├─(以 276a7eff 起底，后并入 f26aadb3)─ main-plus-dev f1e26b3c ─┐
fork dev   842bf9e1 ─┘                                                            ├─ dev 97735b13 ─ b7ba44d6
                                                                                  ┘
```

| 名字 | 提交 | 定位 |
|---|---|---|
| 上游 `main` | `f26aadb3` | `hiddify/hiddify-app` 真正的 tip（含 PR #2367 等） |
| fork `main` | `276a7eff` | 只做上游镜像；**当前落后上游 269 个提交**（见 §11） |
| `main-plus-dev` | `f1e26b3c` | 合并工作的落点，本次的「产物」 |
| `dev` | `b7ba44d6` | fork 主力线，本次把产物落回来 |

合并提交 `97735b13` 的第一父是 `842bf9e1`（旧 dev），第二父是 `f1e26b3c`（`main-plus-dev`）。

---

## 2. 规模

相对**上游 `main`（`f26aadb3`）**：

```
374 files changed, 58809 insertions(+), 2147 deletions(-)
新增 321 / 修改 53 / 删除 0
```

其中 vendor（本轮照搬的第三方包）占大头：

| 目录 | 文件数 | 说明 |
|---|---|---|
| `packages/simple_icons-10.1.3-fixed` | 159 | fork 修的 simple_icons |
| `packages/tray_manager` | 99 | fork 修的托盘库 |

**非 vendor 的真实增量约 61 个新文件**（完整清单见 §10 复核清单）。

---

## 3. 这轮搬了什么（按功能分组）

| 功能 | 承载提交 | 主要落点 |
|---|---|---|
| per-app 代理，**并入上游的 `app_based_routing`**（不重建 `per_app_proxy` 目录） | `9922d800` `79612d9c` `39f639e4` | `lib/features/app_based_routing/**` |
| 读应用的系统标记 / 联网权限 | `9922d800` | `app_based_routing/data/app_package_metadata_*` + Android Kotlin |
| app 列表筛选（不止「系统应用」）与计数 | `79612d9c` | `app_based_routing/domain/app_package_filter.dart` |
| 日志：改用上游的 sink 管线，丢掉 fork 的 repository 层 | `f4763d32` `af26d9fa` | `lib/core/logger/**`（`ring/`、`sinks/`） |
| 流量历史（日历视图）+ 托盘速度 | `5847d5d8` `76b02229` | `lib/features/stats/**`、`lib/features/system_tray/model/tray_speed_layout.dart` |
| 节点搜索 | `da5ee4d7` | `lib/features/proxy/domain/proxy_search.dart`、`widget/proxy_search_overlay.dart` |
| 节点黑名单 | `da5ee4d7` | `proxy/data/node_blacklist_*`、`proxy/notifier/node_blacklist_controller.dart`、`overview/node_blacklist_management_page.dart` |
| 自定义代理（HTTP/SOCKS） | `e987cc1a` | `lib/features/profile/data/custom_proxy_config.dart` |
| 自定义代理并入「手动添加」面板成 tab | `9a3d4c0c` | `profile/add/add_profile_modal.dart`、`profile/add/widgets/add_profile_custom_proxy.dart` |
| macOS 系统代理：断开/切模式时释放 | `53588607` `3bc13c5c`（+ core 侧） | `lib/features/platform_specific/shell_proxy_env.dart`、`hiddify-core` sing-box |
| 备份 / 导出导入 | `67abf7c4` | `lib/features/backup/**`、`profile/model/profile_export_bundle.dart` |
| 设置项：外观 / 全局快捷键 / 网络身份 | `76b02229` `1b2a671f` | `settings/overview/sections/appearance_page.dart`、`network_identity_page.dart`、`lib/features/shortcut/**` |
| 通知 toast 可带动作 + 启动守卫 | `f784ed95` | `lib/core/notification/**` |
| 连接按钮带热重载状态 | `03ce2d55` | `lib/features/connection/**`、`home/widget/connection_button.dart` |
| 路由/外壳/托盘接线 | `eafdfbaa` | `core/router/**`、`features/app/widget/app.dart` |
| DB schema 7 → 9 | `5847d5d8` `642da8ca` | `lib/core/db/**` |
| 翻译：保留上游 ICU key 与复数形式 | `8beebb37` | `assets/translations/**` |
| Android 构建：AGP 8.11.1 + Gradle 8.14 | `bef606cd` | `android/**`、gradle wrapper |
| **Android release 卡闪屏修复** | `03a4a639` | `android/app/proguard-rules.pro` |
| 手动面板高度修复 | `699e41ed` | `profile/add/add_profile_modal.dart`、`core/router/bottom_sheets/**` |
| 工程：本地跨平台构建 / CI | `235f23b0` `28756541` `6e0a3cfe` `55c11655` | `justfile`、`Makefile`、`.github/workflows/**` |

随本次一并进来的、`dev` 线上原有的 fork 提交：`842bf9e1` `eb62c3f0` `55c11655` `6e0a3cfe` `28756541` `235f23b0` `5940e891` `d34b78ab` `18733b37` `2a637196` `e1186b71` `0a4de862`。

---

## 4. 冲突是怎么解的

干跑 `git merge main-plus-dev`（在 dev 上）：**57 个文件冲突**。

加 `-X theirs`（以 `main-plus-dev` 为准）后仍有 **9 个无法自动解决**：

```
hiddify-core
lib/core/logger/logger_controller.dart
lib/core/router/bottom_sheets/widgets/auto_apps_selection_modal.dart
lib/features/app_based_routing/data/app_package_metadata_provider.dart
lib/features/app_based_routing/data/app_package_metadata_repository.dart
lib/features/log/data/log_repository.dart
lib/features/per_app_proxy/model/app_package_info.dart
lib/features/per_app_proxy/overview/per_app_proxy_page.dart
lib/features/profile/widget/profile_tile_main.dart
```

（多为两边都新增、或一边删一边改的 add/add、modify/delete。）

**最终做法**：不逐个人工解，直接

```bash
git checkout dev
git merge --no-commit --no-ff -X theirs main-plus-dev
git read-tree --reset -u main-plus-dev   # 索引+工作区直接置为 main-plus-dev 的树
git diff --cached main-plus-dev          # 必须为空
git commit                               # 得到 97735b13
```

这样 `dev` 的树与设备验证过的产物**逐字节一致**，不用怀疑「解冲突时手抖了」。
事后校验：

```bash
git diff --name-only main-plus-dev dev   # 输出应为空
```

<details>
<summary>raw 冲突全清单（57 个，`-X theirs` 前）</summary>

```
.github/workflows/build.yml
.github/workflows/ci.yml
.gitignore
android/app/src/main/kotlin/com/hiddify/hiddify/PlatformSettingsHandler.kt
android/app/src/main/kotlin/com/hiddify/hiddify/bg/PlatformInterfaceWrapper.kt
android/app/src/main/kotlin/com/hiddify/hiddify/bg/ProxyService.kt
android/app/src/main/kotlin/com/hiddify/hiddify/bg/VPNService.kt
hiddify-core
ios/Runner.xcodeproj/project.pbxproj
justfile
lib/bootstrap.dart
lib/core/analytics/analytics_controller.dart
lib/core/db/db.dart
lib/core/db/db.steps.dart
lib/core/db/schemas/db/drift_schema_v7.json
lib/core/logger/logger_controller.dart
lib/core/notification/in_app_notification_controller.dart
lib/core/preferences/general_preferences.dart
lib/core/router/adaptive_layout/my_adaptive_layout.dart
lib/core/router/bottom_sheets/widgets/auto_apps_selection_modal.dart
lib/core/router/go_router/routing_config_notifier.dart
lib/core/theme/app_theme.dart
lib/features/app/widget/app.dart
lib/features/app_based_routing/data/app_package_metadata_provider.dart
lib/features/app_based_routing/data/app_package_metadata_repository.dart
lib/features/backup/data/backup_scheduler.dart
lib/features/backup/overview/backup_page.dart
lib/features/common/qr_code_dialog.dart
lib/features/connection/notifier/connection_notifier.dart
lib/features/connection/widget/connection_wrapper.dart
lib/features/home/widget/connection_button.dart
lib/features/log/data/log_path_resolver.dart
lib/features/log/data/log_repository.dart
lib/features/log/overview/logs_overview_notifier.dart
lib/features/log/overview/logs_page.dart
lib/features/per_app_proxy/model/app_package_info.dart
lib/features/per_app_proxy/overview/per_app_proxy_page.dart
lib/features/profile/add/widgets/fix_btns.dart
lib/features/profile/model/profile_export_bundle.dart
lib/features/profile/overview/profiles_notifier.dart
lib/features/profile/widget/profile_tile_main.dart
lib/features/proxy/active/active_proxy_card.dart
lib/features/proxy/overview/proxies_overview_notifier.dart
lib/features/proxy/widget/proxy_tile.dart
lib/features/settings/overview/sections/general_page.dart
lib/features/settings/overview/settings_page.dart
lib/features/settings/widget/lan_sharing_tile.dart
lib/hiddifycore/generated/v2/hcore/hcore.pbenum.dart
lib/hiddifycore/generated/v2/hcore/hcore.pbjson.dart
lib/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart
linux/flutter/generated_plugin_registrant.cc
linux/flutter/generated_plugins.cmake
macos/Podfile.lock
pubspec.lock
test/drift/db/generated/schema.dart
test/drift/db/generated/schema_v7.dart
windows/packaging/msix/make_config.yaml
```

</details>

---

## 5. 有意**不**搬的东西

上游已经重写过的地方，照搬 fork 版本会把上游的改动冲掉，所以只搬增量：

- 三态模式下拉框（tristate mode dropdown）
- `getInclude` / `getExclude` / `isSuccess()` 这些死代码
- `PerAppProxyService`（上游改成了 `app_based_routing` 的结构）
- `PlatformInterfaceBridge.kt`（已删）
- fork 自己的 `LoggerController` / `lib/features/log/data/log_repository.dart` 旧日志层（上游的 sink 管线取代）
- fork 自己的 `lib/features/per_app_proxy/` 目录副本（并入 `app_based_routing`）

**约定**：以后合并先算「fork 对上游的**真增量**」再搬，不要整个 `dev` 照搬（见 skill `hiddify-merge-upstream`）。

---

## 6. 数据库 schema

- 版本从 **7 升到 9**，新增了两张/两组 schema 快照：`drift_schema_v8.json`、`drift_schema_v9.json`。
- 迁移里新增的 `from8To9` 用 `_columnExists` 判断列是否存在，避免在对应用户库上重复加列。
- `642da8ca` 专治「两种构建写出来的 v7 库」：修复时会去 heal 这类库，配套有回归测试（`test/drift/**`）。
- `drift_schema_v7.json` 在冲突清单里，说明上游也动过 v7；最终以 fork 侧快照为准。

---

## 7. 只在 release 才暴露的坑（重要）

**症状**：「卡在启动闪屏」，debug 完全正常，只有 release 包复现。

**根因**：不是 `shared_preferences` 的 Dart/native 版本不匹配，而是 **R8 混淆**。

- Flutter 的 gradle 插件对 release 打开 R8（`FlutterPlugin.kt` 里 `releaseBuildType.isMinifyEnabled = true`）。
- `shared_preferences_android` / `path_provider_android` 通过 `package:jni` **按字符串名字**从 Dart 直连 Kotlin。
- R8 看不到这种按名查找，于是把 `kotlin.coroutines.Continuation`（→ `Lh4/c;`）、
  `kotlin.coroutines.intrinsics.CoroutineSingletons` 等重命名/删掉。
- `sharedPreferencesProvider` 在 `runApp` 之前就抛 `NoSuchMethodError`/`ClassNotFoundException`，
  `FlutterNativeSplash.remove()` 永不执行 → 闪屏卡死。
- debug 不跑 R8，所以完全看不出来。

**修法**：`android/app/proguard-rules.pro`（新增）里保留 `package:jni` 按名查找的那几个非 `java.*` 类。
清单来源就是 `jni/lib/src/kotlin.dart` 的 `JClass.forName`。

**教训**：原生产物**必须真的装 release 跑一次**。debug 过 ≠ release 过。

---

## 8. 底部面板：两个 UI 坑

1. `showModalBottomSheet` 的 child 高度来自 modal，而 `AddProfileModal` 外层只有 `SafeArea`，是**无界**的。
   在里面放 `Expanded(TabBarView)` 会撑成**全屏**，原来「半屏内容高」的观感全丢。
   → 改成 `LayoutBuilder` + `SizedBox(height: available * 0.6)`。
2. `showModalBottomSheet` **默认 `useSafeArea: false`**，会对 child 做
   `MediaQuery.removePadding(removeTop: true)`，于是面板内部读到的 `padding.top` 恒为 0，
   自己再包 `SafeArea` 也没用，顶部标题被状态栏盖住。
   → `_show` 加 `useSafeArea` 参数，`AddProfileModal` 的两个调用点传 `useSafeArea: true`。

---

## 9. 子模块

| 子模块 | `dev` 记录的指针 | fork 上的分支 |
|---|---|---|
| `hiddify-core` | `737f287`（`chore: point hiddify-sing-box at the proxy-release fix`） | `main-plus-dev`（本轮新增）、`dev`、`main`、`fix/darwin-system-proxy-cleanup` |
| `hiddify-sing-box` | `a799eff4`（`fix(macos): release the system proxy even with no live inbound`） | `main-plus-dev`（本轮新增）、`dev`、`extended`、`fix/darwin-system-proxy-release` |

- 两个指针原本只在本地，已用**显式 fork URL** 推到 `ShuttleSpace/hiddify-core` / `ShuttleSpace/hiddify-sing-box`。
- `.gitmodules` 里 `hiddify-core` 的 url 仍指**上游**（`ssh://git@github.com/hiddify/hiddify-core`），
  本地 git config 也没覆盖。所以按 fork 克隆子模块时要手动换 URL，否则拿不到 fork 分支上的提交。
- **注意**：`hiddify-core` 的 `dev`（`73225d0`）与 `main-plus-dev`（`737f287`）是**两条分叉线**，
  各自实现了同名的 `SetSystemProxyEnabled`；`dev` 那条多了几个 CI 提交（`625ba9d` fetch sing-box tags 等），
  `main-plus-dev` 那条基于更新的上游。下次合并前要先决定哪条是主。

---

## 10. CI 与产物

### 状态

fork 的 CI **历史上从没成功过**（`gh run list` 里 dev 全是 failure）。本次定位到第一层原因：

```
Because hiddify depends on cupertino_icons >=2.0.0 which requires SDK version ^3.12.0,
version solving failed.
```

- `pubspec.lock` 的 `sdks:` 是 `dart >=3.12.0` / `flutter >=3.44.0`（`cupertino_icons 2.x` 要新 Dart）。
- 而 `.github/workflows/build.yml` 钉的是 `FLUTTER_VERSION: '3.38.5'`（Dart 3.10.x）。
- 结果是 `make linux-amd64-prepare` 在版本求解就死掉，`test` job 失败 → `build` job（`needs: test`）全部跳过。

### 本次改了什么

| 改动 | 说明 |
|---|---|
| `FLUTTER_VERSION: 3.38.5` → `3.44.4` | 与本机一致（Flutter 3.44.4 / Dart 3.12.2），满足 lock 的 `>=3.44.0` |
| 四个签名步骤加 `env.HAS_*` 守卫 | 缺密钥时**跳过**而不是让 job 在 setup 阶段就死 |
| `retention-days: 1` → `30` | 让产物放得久一点，能下载 |

### 签名：**不能**用上游的签名文件

结论：**用不了，也不该用。**

1. **GitHub Actions 的 secrets 属于仓库（或组织）**，fork 不继承上游的 secrets，也没有任何办法读出来。
2. **仓库里根本没有签名材料**。`git ls-files` 里没有 `.jks` / `.p12` / `.pfx`；
   `.gitignore` 明确把它们排除（`windows/sign.pfx`、`windows/sign.cer`、`/cert.pem`、`/key.pem`、`/sign.pfx`），
   提交 `88de65dd`（"add local signing materials"）加的只是 `.gitignore` 条目。
   上游/本机都用「把密钥放本地、被 gitignore」的方式。
3. **即使拿得到也不该用**：Android/Windows 的签名就是应用的身份。用上游的 key 签，等于冒用官方身份；
   同包名同 key 的包能覆盖安装官方版，上架也会被拒。

**android 在没有密钥时的行为**（`android/app/build.gradle`）：

```groovy
boolean hasKeyStore = false
if (keystorePropertiesFile.exists()) { ...; hasKeyStore = true }
...
release {
    if (hasKeyStore) signingConfig signingConfigs.release
    else            signingConfig signingConfigs.debug   // ← 落这里
}
```

所以守卫生效后，CI 出的是 **debug key 签名的 release APK**，可以侧载安装，但**不能上架、也不能覆盖官方版**。

想恢复正式签名，给 fork 加自己的 secrets 即可（`ANDROID_SIGNING_KEY`(base64 jks)、
`ANDROID_SIGNING_STORE_PASSWORD`、`ANDROID_SIGNING_KEY_PASSWORD`、`ANDROID_SIGNING_KEY_ALIAS`）：

```bash
keytool -genkeypair -v -keystore fork.jks -alias fork \
  -keyalg RSA -keysize 2048 -validity 10000
base64 -i fork.jks | gh secret set ANDROID_SIGNING_KEY
```

⚠️ **fork 目前没有任何 secrets / variables**（`gh secret list`、`gh variable list` 都是空）：
所以 macOS 的证书导入、Windows 的 msix 签名都会走「跳过」分支；
`windows-msix-release` 因为 `windows/sign.pfx` 不存在**仍会失败**（`make` 在 msix 这一步中断，
zip/exe 会先产出但不会进 `out/`）。Windows 只是噪声，Android / Linux / macOS 不受影响。

### 产物从哪下载

`build` job 用 `actions/upload-artifact@v6` 传 `retention-days: 30` 的 artifact；
`update-draft` job 再把所有 artifact 合并、写进名为 **`draft` 的 prerelease**：

```
GitHub → Actions → 该次 run → Artifacts          （artifact 下载）
GitHub → Releases → draft                        （prerelease 附件，自动被下一次构建覆盖）
```

`build` job 带 `continue-on-error: true` + `fail-fast: false`，所以单条 matrix 腿失败不会把整次 run 判红；
真正会判红的是 `test` job 和 `update-draft`。

---

## 11. 复核清单

对着这些看（相对上游 `main` 的**非 vendor 新增/修改**）：

**核心**
- [ ] `lib/core/logger/**`（`ring/log_ring.dart`、`sinks/*`）——确认上游的 sink 管线被完整接上，没有残留 fork 的旧日志层
- [ ] `lib/core/db/**` + `lib/core/db/schemas/db/drift_schema_v8.json`、`v9.json`——迁移 7→9 与 `_columnExists`
- [ ] `lib/core/platform/platform_capabilities.dart`
- [ ] `lib/core/theme/appearance_options.dart`（外观种子色接线）

**功能**
- [ ] `lib/features/app_based_routing/**`（per-app 代理并入上游结构）
- [ ] `lib/features/proxy/**`（搜索 `proxy_search.dart`、黑名单 `node_blacklist_*`、`node_search_overlay`）
- [ ] `lib/features/stats/**` + `system_tray/model/tray_speed_layout.dart`（流量历史 / 托盘速度）
- [ ] `lib/features/shortcut/**` + `settings/overview/sections/{appearance,network_identity}_page.dart`
- [ ] `lib/features/backup/**` + `profile/model/profile_export_bundle.dart`
- [ ] `lib/features/profile/data/custom_proxy_config.dart` + `add/widgets/add_profile_custom_proxy.dart`
- [ ] `lib/features/platform_specific/shell_proxy_env.dart`（macOS 代理释放的 Dart 侧）

**平台 / 构建**
- [ ] `android/app/proguard-rules.pro`（release 闪屏的关键）
- [ ] `android/**`（AGP 8.11.1 + Gradle 8.14，mobile_scanner 需要 ≥8.9.1）
- [ ] `justfile`、`Makefile`、`scripts/{build_release,split_macos_arch,watch-macos-proxy}.sh`
- [ ] `.github/workflows/manual-build.yml`、`docs/branching-and-release.md`

**测试**
- [ ] `test/features/app_based_routing/domain/per_app_proxy_*_test.dart`
- [ ] `test/features/proxy/**`（黑名单 engine/repository/model、搜索、overview）
- [ ] `test/features/profile/data/custom_proxy_config_test.dart`

---

## 12. 遗留 / 下次要看

1. **fork 的 `main` 落后上游 269 个提交**（`276a7eff` vs `f26aadb3`）。
   按 skill 的模型 `main` 应该只快进上游镜像，建议下次开工前先把它 fast-forward 到上游。
   这也解释了为什么「合并基线」看着对不上：真正被并入的上游是 `f26aadb3`，不是 `276a7eff`。
2. **fork 没有任何 CI secrets**（见 §10），macOS/Windows 目前是「跳过签名」状态。
3. **Windows msix 腿仍会失败**（缺 `windows/sign.pfx`）。要绿的话需要自签证书（`make_config.yaml` 里有注释示例：`publisher: CN=Hiddify-Test`）。
4. **`hiddify-core` 的 `dev` / `main-plus-dev` 两条分叉线**没合，见 §9。
5. **`pubspec.yaml` 的 `environment` 是骗人的**：写着 `sdk: ^3.10.4` / `flutter: ^3.38.5`，
   但 `pubspec.lock` 实际要求 `>=3.12.0` / `>=3.44.0`。本次没改（只改了 CI 的 `FLUTTER_VERSION`），
   留着容易让下一个人以为 3.38.5 能用。
6. **Issue 6**「连接显示已连接但提示超时」——根因未确认，仍缺复现信息。
7. `lib/bootstrap.dart` 的 core 初始化没有超时（只有 `preferences` 那步会 rethrow）；
   想要更硬的启动保障可以加个 timeout。

---

## 13. 复现与验证命令

```bash
# 确认 dev 与验证过的产物一致
git diff --name-only main-plus-dev dev        # 期望：空

# 本地出 release 包并装机（会从子模块编 core）
just android
# → build/app/outputs/flutter-apk/app-release.apk（无 keystore，debug key 签名）

# 看 CI
gh run list -L 5
gh run watch <run-id>
```

设备环境：Xiaomi `24117RK2CC`（`product:zorn`），包名 `app.hiddify.com`，
launcher `app.hiddify.com/com.hiddify.hiddify.MainActivity`。
