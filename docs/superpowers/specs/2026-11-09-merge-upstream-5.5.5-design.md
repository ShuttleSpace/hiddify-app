# 合并上游 v5.5.5 到 fork `dev` 的设计

- **日期**：2026-11-09
- **状态**：待批准
- **目标基线**：`hiddify/hiddify-app` 的 `v5.5.5`（`7804cada`）
- **落点**：`ShuttleSpace/hiddify-app` 的 `dev`
- **合并方式**：镜像 `main` + 集成分支（方案 B）

---

## 1. 要做什么，为什么

fork 的 `dev` 停在 5.1.0，代码基线仍是 2026-10-19 的上游 `f26aadb3`。上游此后发布了
5.5.0、5.5.1、5.5.5，Proxy 详情/分享、Profile 分享、连接状态、设置页、Windows/iOS 构建
都有较大改造。本轮要把上游 5.5.5 的代码完整拿进来，同时保留 fork 自己的功能，把鸿蒙
分支一起落进 `dev`，并让 CI 打出的安装包真正带上 fork 的 core。

**成功的样子**：`dev` 的树 = 上游 5.5.5 的全部行为 + fork 的既有功能 + 鸿蒙支持；
`flutter analyze` 0 error、`flutter test` 全过、release 包能装能连、系统代理在断开时
确实释放；上游新增的代码没有被冲突解决静默丢掉。

## 2. 非目标

- 不把 fork 的改动推回上游，也不改上游仓库。
- 不重做 fork 功能的设计；上游已经取代的旧实现可以删，但要在合并记录里写清楚。
- 不在本轮引入新的产品功能（MCP、鸿蒙、release 流程都按现状并入）。
- 不追 `upstream/main` 在 `v5.5.5` 之后的 3 个提交；需要时下一轮再跟。
- 鸿蒙的**构建验证**不在本轮：本机 OHOS 工具链已损坏，只保证代码并入、
  依赖能解析、Dart 层能过 analyze；出包验证另开任务。

## 3. 现状与约束

### 3.1 拓扑

```
上游 main  f26aadb3（10-19，共同祖先）
          ├─ 278 commits ─ v5.5.0 ─ v5.5.1 ─ v5.5.5（7804cada）
fork dev  f26aadb3 ─ 190 个 fork 提交 ─ ce6d5898（5.1.0）
fork ohos 8d27fc01 ─ 6 个鸿蒙提交 ─ 7f6f7358（比 dev 少 4 个提交）
```

- fork `main` 当前 `276a7eff`，是 `v5.5.5` 的祖先，可以 `--ff-only`。
- `origin/main` 是 `f26aadb3`，同样可以快进。
- 版本号：fork 现在 `5.1.0+50100`，上游 `5.5.5+50505`；同包名 `app.hiddify.com`
  要求 versionCode 单调，`50505 > 50100`，直接采用上游版本号。

### 3.2 合并规模（`v5.5.5` × `dev` 试算）

- 上游侧：417 个文件、+41695 / -7670。
- fork 侧：自共同祖先 473 个文件有改动。
- 两边都改过：41 个文件；其中 32 个会真冲突。
- 冲突文件分类：
  - 12 个翻译 JSON；
  - proxy 3 个（`proxy_repository`、`proxies_overview_page`、`proxy_tile`）；
  - profile 4 个（`add_profile_modal`、`profile_details_*`）；
  - 连接 2 个、`app.dart`、`settings_page`、`system_tray_notifier`；
  - `hiddify_core_service.dart`；
  - 构建/平台：`.github/workflows/build.yml`、`Makefile`、`pubspec.yaml`、
    `pubspec.lock`、`macos/Podfile.lock`、`ios/Runner.xcodeproj/project.pbxproj`、
    `windows/packaging/msix/make_config.yaml`；
  - `hiddify-core` 子模块；
  - 1 个测试。
- 子模块：fork `hiddify-core@737f287` 与上游 `ad83d757` 分叉；fork 侧 3 个提交
  （`SetSystemProxyEnabled`、CI 修复、sing-box 指针），上游侧 151 个。
  fork 的 `73225d0`（core 的 `dev` 线）另有两个修复：代理释放的单一 owner /
  容忍清理失败、sing-box 的 residue-as-stranger-proxy。

### 3.3 环境约束

- 本机 Flutter **3.47.2 / Dart 3.13.2**（puro 的 `default` 和 `stable` 都是它）；
  CI 现在钉 **3.44.4 / Dart 3.12.2**。
- 鸿蒙分支的 `pubspec.lock` 要求 `dart >=3.11 <3.13`、`flutter >=3.41`。
  3.47.2 会越过 Dart 上界，合并后需要重新求解；若某个 ohos 依赖拒绝 3.13，
  退回 3.44.4（装到 puro）并同步 CI。
- pub 镜像 `pub.flutter-io.cn` 可达；本机 `PUB_HOSTED_URL` 已指向它。
- `puro` 的 `ohos` 环境已损坏（`Wrong full snapshot version`，SDK 也不在默认路径），
  所以鸿蒙构建验证后置。
- `github.com` 的 git HTTPS 此前不可达，SSH 可用；core 的发布资产走 HTTPS 下载，
  合并后要单独确认 CI 能从 `ShuttleSpace/hiddify-core` 拉到 core。
- CI 只在 `main` / `dev` / 两个旧分支上触发，没有 `workflow_dispatch`；
  `dev` 同时是分支名和滚动 release 的 tag 名，所有命令都要写全 `refs/heads/dev`。

## 4. 考虑过的做法

### A. 直接在 `dev` 上合并（未选）

`git merge v5.5.5` 直接落在 `dev`，解 32 个冲突。

- 优点：步骤最少。
- 否决原因：冲突解决过程直接在主力分支上，出错回退成本高；32 个冲突一次面对，
  最容易重演上次「冲突全判给 fork、静默丢上游 179 行」的问题。

### B. 镜像 `main` + 集成分支（选中）

先把 `main` 快进到 `v5.5.5`，从它开 `merge/v5.5.5`，在集成分支上合 `dev`；验证通过后
再把 `dev` 快进到集成分支，最后并入 `feat/ohos-support`。

- 优点：`main` 始终是上游镜像；集成过程可暂停、可回退、可逐文件复查；`dev` 在验证前
  不被污染；与上一次成功的合并流程一致。
- 代价：多一个分支和一次合并；冲突仍要手工解。

### C. 按功能重放（未选）

从 `v5.5.5` 起，把 fork 功能按组重新落上去。

- 优点：保真度最高，可以顺手淘汰被上游取代的实现。
- 否决原因：190 个 fork 提交 / 473 个文件，工作量远大于本轮；容易漏掉 router、tray、
  preferences 这类接线代码；上游已经重写了 proxy/profile 的一半，逐功能重放等于重做设计。

## 5. 选定的流程

### 5.1 准备与快照

```bash
git tag pre-merge-5.5.5 refs/heads/dev          # 回退锚点
git status                                      # 只允许未跟踪的 ohos/、.workbuddy/
```

- 保留当前未跟踪目录，不纳入合并。
- 记录 `refs/heads/dev`、`refs/heads/feat/ohos-support`、
  `hiddify-upstream/main`、`v5.5.5` 的提交号到合并记录。

### 5.2 把 `main` 快进到 `v5.5.5`

```bash
git checkout main
git merge --ff-only v5.5.5
git push origin main:main
```

- `main` 与上游逐字节一致，不携带任何 fork 改动。
- `main` 上的上游 CI 在 fork 上会红（缺签名/发布凭据），这是已知状态，不作为本轮门槛。

### 5.3 开集成分支并合并

```bash
git checkout -b merge/v5.5.5 v5.5.5
git merge --no-ff --no-commit refs/heads/dev
```

- 第一父是上游 `v5.5.5`，第二父是 `dev`；合并结果就是新 `dev`。
- **禁止** `-X theirs` / `-X ours` / `read-tree --reset` 一把梭；每个冲突按下表逐文件处理。
- 冲突之外，`git diff --stat` 与 `git status` 要逐项过一遍，确认没有意外删除。

### 5.4 冲突解决原则

1. **默认两边都要**：上游的新结构 + fork 的功能参数/入口。
2. 用 `git merge-file --diff3` 做三方合并，输入是 `v5.5.5` / 共同祖先 / `dev`；
   冲突数会小到能逐处判断。
3. 上游删掉、fork 保留的代码：先确认是上游的 UX/架构决策还是 fork 功能的一部分；
   前者跟随上游，后者保留并在合并记录里写明。
4. 生成的/可再生的文件不手抄：`pubspec.lock`、`Podfile.lock`、`ios/*.pbxproj`、
   generated protobuf 尽量用工具重新生成或取上游后验证。
5. 翻译文件按 slang 的 key 合并：先保证 `en` 的 key 完整，再跑 `dart run slang`
   与 `analyze`；`en` 的改动单独提交。
6. **fork 的系统代理释放必须保留**：Dart 侧 `connection_notifier` /
   `connection_repository` 的调用、`hiddify_core_service` 的
   `releaseSystemProxy()`，以及 core 的 `SetSystemProxyEnabled`。上游 5.5.5 里
   这个 RPC 仍是注释掉的，不能跟随上游删掉。

### 5.5 逐文件策略

| 文件 | 策略 |
|---|---|
| `assets/translations/*.i18n.json`（12） | 取上游 key 结构，补回 fork 的 key；`dart run slang` 后跑缺失/未使用检查 |
| `lib/features/proxy/**`（3） | 取上游的测速缓存、"失败原因"、详情页；保留 fork 的节点搜索、黑名单过滤与跳转 |
| `lib/features/profile/add/add_profile_modal.dart` | 取上游新增的分享/导入入口；保留 fork「自定义代理」tab 与半屏高度修复 |
| `lib/features/profile/details/**`（3） | 取上游的实时 proxy 展示；保留 fork「保存时保留编辑」的修复 |
| `lib/features/connection/**`（2） | 取上游的状态/错误处理；保留 fork 的 shell 代理提示、热重载状态与系统代理释放 |
| `lib/features/app/widget/app.dart` | 取上游的更新检查与 SnackBar 接线；保留 fork 的路由、托盘、外观种子色 |
| `lib/features/settings/overview/settings_page.dart` | 取上游新增的快捷设置/连接共享；保留 MCP、快捷键、外观、网络身份入口 |
| `lib/features/system_tray/notifier/system_tray_notifier.dart` | 取上游通知生命周期；保留 fork 的托盘速度布局 |
| `lib/hiddifycore/hiddify_core_service.dart` | 三方合并：取上游新 RPC/日志/错误映射；保留 fork 黑名单、MCP 与 `releaseSystemProxy` |
| `pubspec.yaml` | 版本改 `5.5.5+50505`；保留 fork 依赖（MCP、hotkey、ohos 相关）；取上游新增依赖与 `dependency_overrides`（`http2`、`flutter_animate`） |
| `pubspec.lock` | 不手合，`flutter pub get` 重新求解 |
| `.github/workflows/build.yml` | 保留 fork 的 `dev` tag 发布、缺凭据跳过签名；只吸收不依赖上游 secrets 的新步骤；Flutter 版本与本机/CI 统一（见 5.9） |
| `Makefile` | 取上游新目标；保留 fork 的 AppImage 权限修复与本地构建配方；core 下载地址改指向 fork（见 5.6） |
| `macos/Podfile.lock`、`ios/*.pbxproj` | 取上游后重新 `pod install` 验证；网络不可达时先取上游并在 CI 上确认 |
| `windows/packaging/msix/make_config.yaml` | 取上游新配置；保留 fork「无证书时跳过 msix」的行为 |
| `test/features/profile/data/profile_repository_test.dart` | 按合并后的 API 调整，不改断言意图 |
| `hiddify-core` | 见 5.6 |

### 5.6 子模块与 core 二进制

**源码合并**

1. 以 `737f287` 为 app 的基准（它基于较新的上游，且已包含同一份
   `SetSystemProxyEnabled` 实现）。
2. 把 core `dev` 线的独有修复合进来：`16a16df`（代理释放单一 owner、容忍清理失败）、
   `9840cfc`（CI 不递归子模块）；能自动合的自动合，冲突处确认两份系统代理实现等价。
3. 把 fork 的 core 分支合到上游 `ad83d757` 上，得到新的 core 指针。
4. `hiddify-sing-box` 同样合并两条修复线：fork 的 `a799eff4`（proxy-release fix）
   与 `656b78d`（residue-as-stranger-proxy fix），再对上游新指针。
5. 新提交推到 `ShuttleSpace/hiddify-core` / `ShuttleSpace/hiddify-sing-box`，
   再把 app 的子模块指针指过去。
6. 本地 `git submodule update --init --recursive --force` 后确认所有嵌套子模块干净。

**发布与引用**

1. 在 `ShuttleSpace/hiddify-core` 上给合并后的 core 打 `v5.5.5` tag（prod）与
   `dev`/draft tag（滚动），让 Release workflow 产出 `hiddify-lib-*` 与 Android 包。
2. `Makefile` 的 `CORE_URL` / `ANDROID_CORE_URL` 从 `hiddify/hiddify-core` 改到
   `ShuttleSpace/hiddify-core`。
3. `dependencies.properties` 改为 `core.version=5.5.5`。
4. `ANDROID_CORE_VERSION=5.0.0` 是 fork 针对旧 Kotlin 绑定的临时钉法；合并后先试上游
   5.5.5 的 AAR 能否编译，能编译就删掉这个钉法，不能就改成 `5.5.5` 并记录原因。
5. 验证门槛里必须确认 CI 真的从 fork 的 release 拉到 core，并且
   `SetSystemProxyEnabled` 在 release 包里可用。

### 5.7 并入鸿蒙分支

```bash
git checkout merge/v5.5.5
git merge --no-ff refs/heads/feat/ohos-support
```

- 预期冲突：`pubspec.yaml` / `pubspec.lock`、`.gitignore`、`lib/bootstrap.dart`、
  `macos/Podfile.lock`、`Makefile`、`windows/packaging/msix/make_config.yaml`。
- 原则：鸿蒙依赖与插件实现全部保留；上游新增的依赖照常保留；版本号仍用 5.5.5。
- `.puro.yaml`（`env: ohos`）会随分支进来；它只在 puro 下生效，本轮不依赖它，
  用显式 Flutter 路径跑 pub get / analyze。
- `ohos/` 只提交源码与配置，构建产物（`build/`、`oh_modules/`、`node_modules/`、
  `secrets/` 中的密钥）继续忽略。
- **本轮不做出包验证**：本机 OHOS SDK/引擎坏了，修复工具链另开任务；
  合并后只需 `flutter pub get` 能解析 ohos 依赖、`flutter analyze` 不因鸿蒙接入报错。

### 5.8 子模块 URL 与 CI 触发

- `dev` 的 `.gitmodules` 改为 `ssh://git@github.com/ShuttleSpace/hiddify-core`，
  core 内的 `hiddify-sing-box` / `ray2sing` 也改为 ShuttleSpace 的 URL；
  这样新克隆和 CI 都能拿到 fork 的提交。`main` 保持上游 URL，不携带 fork 改动。
- 集成期间把 `merge/v5.5.5` 临时加进 `.github/workflows/ci.yml` 的 push 分支
  （只在集成分支上提交），让 CI 能跑；验证通过后决定是保留 `merge/**` 触发，
  还是删掉、靠 `dev` 的 push 跑最终一遍。
- 所有命令写全 `refs/heads/dev` / `refs/tags/dev`，避免分支和 tag 同名歧义。

### 5.9 验证通过后落回 `dev`

```bash
git checkout dev
git merge --ff-only merge/v5.5.5      # 集成分支包含 dev 作为父提交，可快进
git push origin refs/heads/dev
```

- 若 `dev` 在集成期间有新提交，改为 `git merge --no-ff merge/v5.5.5`。
- 推送 `dev` 会触发滚动 release，确认 CI 与 release 资产正常后再结束本轮。

## 6. 验证门槛

按顺序，前一项不过不进下一项：

1. `flutter pub get` 干净完成。先用本机 3.47.2；若 ohos 依赖的 SDK 上界拒绝 Dart 3.13，
   装 3.44.4 重来，并把 CI 的 `FLUTTER_VERSION` 同步成实际使用的版本。
2. `dart run slang` 成功；翻译缺失/未使用报告里没有新增的 `en` 缺口。
3. `flutter analyze`：**0 error**。
4. `flutter test`：全部通过。
5. **行集合审计**：对 41 个两边都改过的文件，计算
   `v5.5.5` 相对共同祖先新增的行，在合并结果中不存在的部分；每一行都要能解释
   （要么是有意替换，要么是 bug，必须补回）。上一次合并就是这样发现丢了 179 行。
6. **fork 功能回归**：节点搜索、节点黑名单、per-app 路由、流量历史/托盘速度、
   全局快捷键、备份导出导入、自定义代理、通知、MCP 设置页、系统代理释放，
   逐项跑对应测试或手工冒烟。
7. **core 产物检查**：从 `ShuttleSpace/hiddify-core` 的 release 能下载到对应平台的
   core；`dependencies.properties` / `Makefile` 指向正确；macOS 断开连接或切模式后
   系统代理确实释放。
8. release 包验证：至少 Android release APK 装机（能过闪屏、首页/设置可渲染、能连接）；
   macOS 能构建并启动一次。
9. CI：集成分支上 `test` + 四条 build 腿全绿；落回 `dev` 后再确认一遍滚动 release。
10. 鸿蒙：**本轮不做**，记录为后续任务（工具链修复后再补）。

## 7. 回滚

- `dev` 在验证前不被修改；出问题直接丢掉 `merge/v5.5.5`，`dev` 回到 `pre-merge-5.5.5`。
- 子模块指针在合并记录里留旧值，可单独回退。
- core 的新 tag / release 不删除，便于定位；app 侧指针回退即可。
- `main` 的快进是上游镜像，回退无意义也不影响 `dev`。
- 推送 `dev` 之前不删任何旧 tag/release。

## 8. 交付物

- 合并后的 `dev`（含上游 5.5.5、fork 功能、鸿蒙支持），版本 `5.5.5+50505`。
- `docs/merge-notes/2026-11-XX-upstream-5.5.5.md`：拓扑、冲突逐项结论、
  行集合审计结果、被有意替换的上游代码、子模块指针、core 发布、验证记录、遗留问题。
- 如本轮确认了新的合并规则，更新 `docs/branching-and-release.md`
  （尤其是子模块 URL 与 core 发布来源）。

## 9. 风险

| 风险 | 应对 |
|---|---|
| 冲突解错、静默丢上游代码 | 逐文件三方合并 + 行集合审计 + 上游新增能力逐项冒烟 |
| fork 功能被上游重构挤掉 | 5.6 的功能回归清单 + 现有测试 |
| core 两条线合错，代理释放失效 | 先确认上游是否已自带；合并后本地跑 macOS 断开/切模式验证 |
| core release 资产拉不到，CI 断 | 先手工 `curl` 验证 fork release URL，再跑 CI；保留旧 URL 作为回退 |
| 翻译 key 冲突导致编译失败 | `dart run slang` 为强制门槛 |
| Flutter 3.47.2 与 ohos 依赖的 SDK 上界冲突 | 先试 3.47.2；失败退回 3.44.4，并同步 CI |
| Windows/macOS 签名步骤依赖上游 secrets | 保留 fork 的「缺凭据跳过」守卫，不引入上游专属凭据 |
| 鸿蒙分支落后 4 个 dev 提交 | 先合 5.5.5 再合 ohos，冲突集中在 pubspec/bootstrap，逐项解 |
| 鸿蒙构建验证缺失 | 本轮明确后置，合并记录里列为遗留；不要声称已出包验证 |

## 10. 留给实现者的决定

- 上游新增的 Windows 签名/App Store/VirusTotal 步骤，逐个判断「无上游凭据时是否
  可跳过」；不能跳过的就不吸收。
- `macos/Podfile.lock` 与 `ios/Runner.xcodeproj` 优先重新生成；本机网络不允许时，
  以上游版本为准并在 CI 上验证。
- 上游生成代码（`lib/hiddifycore/generated/**`）优先取上游；若 fork 的 MCP/hiddifyctl
  需要新接口，再按上游工具链重新生成。
- Flutter 版本先 3.47.2、失败回退 3.44.4；无论选哪个，本机与 CI 必须一致。
- 合并提交的拆分粒度：代码合并一个提交，翻译修复一个提交，子模块 URL / core 指针一个
  提交，鸿蒙并入一个提交，版本号/发布记录一个提交。
