# 合并上游 v5.5.5 到 fork dev 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `hiddify/hiddify-app` 的 `v5.5.5` 全部代码合进 `ShuttleSpace/hiddify-app` 的 `dev`，保留 fork 全部功能并把鸿蒙分支一并并入，让 CI 打出的安装包带 fork 的 core。

**Architecture:** 方案 B——先把 `main` 快进到 `v5.5.5`（保持上游镜像），从它开 `merge/v5.5.5` 集成分支，在分支上合 `dev` 并逐文件三方合并，通过全部验证门槛后再把 `dev` 快进到集成分支，最后并入 `feat/ohos-support`。所有改动经行集合审计，杜绝静默丢上游代码。

**Tech Stack:** Git（merge / merge-file --diff3）、Flutter/Dart、slang、hiddify-core 子模块（Go）、GitHub Actions、GitHub Releases。

**Spec:** `docs/superpowers/specs/2026-11-09-merge-upstream-5.5.5-design.md`（设计文档与计划一同旅行，执行者两者都读）

## Global Constraints

- 合并基线 = `v5.5.5`（`7804cada`）；共同祖先 = `f26aadb3`。
- 禁止 `-X theirs` / `-X ours` / `git read-tree --reset` 一把梭；每个冲突逐文件三方合并。
- 版本号改 `5.5.5+50505`（同包名 `app.hiddify.com`，versionCode 必须涨）。
- Flutter/Dart 版本：先用本机 3.47.2（Dart 3.13.2）；若 ohos 依赖的 `dart <3.13` 上界拒绝，退回 3.44.4 并同步 CI 的 `FLUTTER_VERSION`；本机与 CI 必须一致。
- fork 的系统代理释放（`releaseSystemProxy` + core `SetSystemProxyEnabled`）必须保留，上游 5.5.5 里该 RPC 仍是注释掉的。
- `main` 始终上游镜像，不携带 fork 改动；`dev` 的 `.gitmodules` 改用 ShuttleSpace fork。
- 翻译改动先保证 `en` 完整，`dart run slang` 为强制门槛；`en` 的改动单独提交。
- 鸿蒙本轮只合代码、保证依赖能解析、analyze 不报错；**不出包验证**。
- 所有涉及 `dev` 的 git 命令写全 `refs/heads/dev` / `refs/tags/dev`，避免分支与滚动 release tag 同名歧义。

## Review Focus

1. **上游新增代码被冲突解决静默丢掉**：行集合审计（Task 13）逐文件核对上游 5.5.5 相对共同祖先新增的行是否还在合并结果中；上次合并就是靠它发现丢了 179 行。
2. **fork 功能被上游重构挤掉**：节点搜索/黑名单、per-app 路由、流量历史/托盘速度、快捷键、备份、自定义代理、MCP、系统代理释放（Task 4–6、8、18）。
3. **core 二进制与 Dart 侧不匹配**：CI 实际从 `ShuttleSpace/hiddify-core` 拉到 core，且 `SetSystemProxyEnabled` 在发布包里可用（Task 15、18 门槛 7）。
4. **翻译 key 冲突导致编译失败或运行时 fallback**：`dart run slang` 必须 0 error，`en` 的 key 集合是上游与 fork 的并集（Task 3）。
5. **Flutter 版本不一致导致 `pubspec.lock` 在不同机器无法复用**：本机与 CI 的 `FLUTTER_VERSION` 必须一致，lock 随版本重解并提交（Task 12、19）。

---

## 准备工作

### Task 0: 环境与快照

**Files:**
- 仅执行命令，不改动文件（除 tag）

**Interfaces:** 无

- [ ] **Step 1: 记录当前各引用点并提交号**
  ```bash
  git rev-parse HEAD refs/heads/dev refs/heads/feat/ohos-support \
    hiddify-upstream/main v5.5.5
  ```
  Expected: 打印 5 个 commit 号，分别记到合并记录。

- [ ] **Step 2: 打回退锚点 tag**
  ```bash
  git tag pre-merge-5.5.5 refs/heads/dev
  ```

- [ ] **Step 3: 确认工作区干净（除未跟踪目录）**
  ```bash
  git status --short
  ```
  Expected: 只剩未跟踪的 `ohos/`、`.workbuddy/`；无已修改/已暂存的已跟踪文件。

- [ ] **Step 4: 确认 Flutter 版本与 pub 镜像**
  ```bash
  ~/.puro/envs/default/flutter/bin/flutter --version
  echo "$PUB_HOSTED_URL $FLUTTER_STORAGE_BASE_URL"
  ```
  Expected: 打印 Flutter 3.47.2 / Dart 3.13.2；`PUB_HOSTED_URL=https://pub.flutter-io.cn`。

- [ ] **Step 5: 提交（仅 tag，已在 Step 2 本地建好）**
  ```bash
  git push origin refs/tags/pre-merge-5.5.5
  ```

### Task 1: 把 `main` 快进到 `v5.5.5`

**Files:**
- 仅移动 `main` 指针

- [ ] **Step 1: 切到 main 并快进**
  ```bash
  git checkout main
  git merge --ff-only v5.5.5
  git push origin refs/heads/main
  ```
  Expected: 快进成功，`git rev-parse refs/heads/main` == `v5.5.5`；`git diff hiddify-upstream/main refs/heads/main` 为空。

---

## 集成阶段

### Task 2: 开集成分支并执行合并（暂停在冲突态）

**Files:**
- 创建分支 `merge/v5.5.5`，不提交

- [ ] **Step 1: 开分支并合并（不自动提交）**
  ```bash
  git checkout -b merge/v5.5.5 v5.5.5
  git merge --no-ff --no-commit refs/heads/dev
  ```
  Expected: 退出码非 0，停在冲突态；`git status --short` 含 32 个 `UU`/冲突标记（12 翻译 + proxy 3 + profile 4 + connection 2 + app.dart + settings + system_tray + core_service + 构建若干 + hiddify-core + 1 测试）。

- [ ] **Step 2: 把冲突文件清单存到合并记录**
  ```bash
  git diff --name-only --diff-filter=U > /tmp/conflicts.txt
  wc -l /tmp/conflicts.txt
  ```
  Expected: 与 Task 2 Step 1 的 32 个一致；把清单粘贴进 `docs/merge-notes/2026-11-XX-upstream-5.5.5.md`。

- [ ] **Step 3: 暂存本任务（不提交）**
  不提交；后续 Task 3–12 逐个解冲突后统一或分批提交。

### Task 3: 翻译文件（12 个 `assets/translations/*.i18n.json`）

**Files:**
- Modify: `assets/translations/{ar,en,es,fa,fr,id,pt-BR,ru,tr,zh-CN,zh-TW}.i18n.json`、`en` 优先

**Interfaces:**
- Consumes: 上游 5.5.5 的 key 结构、fork `dev` 的 key 集合
- Produces: 合并后每个 locale 的 key 是上游 ∪ fork，`en` 完整且单独提交

- [ ] **Step 1: 取上游的 `en` 为基准，补回 fork 的 `en` key**
  对每个冲突的 `en.i18n.json`：用 `git merge-file --diff3` 合并；fork 新增的 key（搜索、黑名单、MCP、快捷键、外观、网络身份、自定义代理等）保留进 `en`。
  ```bash
  for f in assets/translations/en.i18n.json; do
    git show v5.5.5:$f > /tmp/cur.json
    git show f26aadb3:$f > /tmp/base.json
    git show refs/heads/dev:$f > /tmp/other.json
    git merge-file --diff3 -L upstream -L base -L fork /tmp/cur.json /tmp/base.json /tmp/other.json -o $f
  done
  ```
  Expected: 解决 `en` 冲突标记，fork key 全部存在。

- [ ] **Step 2: 其余 10 个 locale 同样合并**
  对每个非 `en` locale 执行同样的三方合并；fork 有而上游没有的 key 补齐对应译文（没有译文的留英文 fallback，slang 会兜底）。

- [ ] **Step 3: 生成并检查**
  ```bash
  ~/.puro/envs/default/flutter/bin/flutter pub get
  dart run slang
  ```
  Expected: `slang` 成功；`assets/translations/` 下生成的 `_missing_translations*.json` / `_unused_translations*.json` 没有新增的 `en` 缺口。

- [ ] **Step 4: 提交 `en` 单独成一次**
  ```bash
  git add assets/translations/en.i18n.json
  git commit -m "feat(i18n): merge upstream 5.5.5 translation keys, en first"
  ```

- [ ] **Step 5: 提交其余 locale**
  ```bash
  git add assets/translations/*.i18n.json
  git commit -m "feat(i18n): merge upstream 5.5.5 locales, keep fork keys"
  ```

### Task 4: Proxy 功能（3 个文件）

**Files:**
- Modify: `lib/features/proxy/data/proxy_repository.dart`、`lib/features/proxy/overview/proxies_overview_page.dart`、`lib/features/proxy/widget/proxy_tile.dart`

**Interfaces:**
- Consumes: 上游 5.5.5 的测速缓存/"失败原因"/详情；fork `dev` 的 `proxy_search`/`node_blacklist`
- Produces: 保留 fork 的搜索、黑名单过滤、跳转；不破坏上游新增能力

- [ ] **Step 1: 三方合并三个文件**
  对每个文件 `git merge-file --diff3`（输入 v5.5.5 / f26aadb3 / dev）。优先保留上游的结构性改动（测速排序、失败原因展示），把 fork 的搜索/黑名单调用与过滤逻辑接回对应位置。

- [ ] **Step 2: 确认 fork 入口仍在**
  检查 `proxies_overview_page.dart` 仍有搜索入口与黑名单管理入口；`proxy_tile.dart` 仍有黑名单视觉标记；`proxy_repository.dart` 仍暴露搜索与黑名单方法。

- [ ] **Step 3: 运行相关测试**
  ```bash
  ~/.puro/envs/default/flutter/bin/flutter test test/features/proxy
  ```
  Expected: 全部通过（搜索、黑名单相关 widget/model 测试）。

- [ ] **Step 4: 提交**
  ```bash
  git add lib/features/proxy
  git commit -m "feat(proxy): keep fork search/blacklist on top of upstream 5.5.5"
  ```

### Task 5: Profile 功能（4 个文件）

**Files:**
- Modify: `lib/features/profile/add/add_profile_modal.dart`、`lib/features/profile/details/profile_details_notifier.dart`、`lib/features/profile/details/profile_details_page.dart`、`lib/features/profile/data/profile_repository.dart`（注：`profile_repository.dart` 能自动合，也一并核对）

**Interfaces:**
- Consumes: 上游 5.5.5 的分享/导入入口、实时 proxy 展示
- Produces: 保留 fork 自定义代理 tab、半屏高度修复、保存时保留编辑

- [ ] **Step 1: 三方合并 `add_profile_modal.dart`**
  取上游新增的分享/导入入口；保留 fork「自定义代理」tab（`add_profile_custom_proxy.dart` 接线）与 `LayoutBuilder`/`SizedBox(0.6)` 高度修复。

- [ ] **Step 2: 三方合并 `profile_details_*`**
  取上游的实时 proxy 展示；保留 fork「保存时保留编辑」的修复（`2c73020c` 行为）。

- [ ] **Step 3: 运行 profile 测试**
  ```bash
  ~/.puro/envs/default/flutter/bin/flutter test test/features/profile
  ```
  Expected: 全部通过；特别确认 `test/features/profile/data/profile_repository_test.dart`（它也在冲突清单里）与合并后 API 一致。

- [ ] **Step 4: 提交**
  ```bash
  git add lib/features/profile
  git commit -m "feat(profile): keep fork custom-proxy tab on top of upstream 5.5.5"
  ```

### Task 6: 连接与系统代理释放（2 个文件）

**Files:**
- Modify: `lib/features/connection/notifier/connection_notifier.dart`、`lib/features/connection/data/connection_repository.dart`

**Interfaces:**
- Consumes: 上游 5.5.5 的连接状态/错误处理
- Produces: 保留 fork 的 shell 代理提示、热重载状态，以及 `_releaseSystemProxy` / `releaseSystemProxy()` 调用

- [ ] **Step 1: 三方合并两个文件**
  取上游「连接前先读 ref」、提前置 `Connecting`、失败按 `error` 记日志；保留 fork 在 `connection_notifier.dart:63/210/221/233/236` 的 `_releaseSystemProxyForModeChange` / `_releaseSystemProxy` 调用，以及热重载状态、shell 代理提示。

- [ ] **Step 2: 确认系统代理释放未被删**
  ```bash
  grep -n "releaseSystemProxy\|_releaseSystemProxy" \
    lib/features/connection/notifier/connection_notifier.dart \
    lib/features/connection/data/connection_repository.dart
  ```
  Expected: 至少出现设计文档 §5.4 列出的调用点。

- [ ] **Step 3: 运行连接测试**
  ```bash
  ~/.puro/envs/default/flutter/bin/flutter test test/features/connection
  ```
  Expected: 全部通过。

- [ ] **Step 4: 提交**
  ```bash
  git add lib/features/connection
  git commit -m "feat(connection): keep fork system-proxy release on top of upstream 5.5.5"
  ```

### Task 7: 外壳接线 `lib/features/app/widget/app.dart`

**Files:**
- Modify: `lib/features/app/widget/app.dart`

- [ ] **Step 1: 三方合并**
  取上游的更新检查（update）与 `scaffoldMessengerKey`/`SnackBarHost` 接线；保留 fork 的路由配置、`AppearanceOptions` 外观种子色、黑名单 guard、流量记录器 `ref.listen`。

- [ ] **Step 2: 编译确认**
  ```bash
  ~/.puro/envs/default/flutter/bin/flutter analyze lib/features/app/widget/app.dart
  ```
  Expected: 无 error。

- [ ] **Step 3: 提交**
  ```bash
  git add lib/features/app/widget/app.dart
  git commit -m "feat(app): merge upstream update/SnackBar wiring with fork router/appearance"
  ```

### Task 8: 设置页与 MCP/快捷键入口

**Files:**
- Modify: `lib/features/settings/overview/settings_page.dart`

- [ ] **Step 1: 三方合并**
  取上游新增的快捷设置/连接共享（LAN sharing 行）；保留 fork 的 MCP 入口（`lib/features/mcp`）、全局快捷键、外观、网络身份设置入口。

- [ ] **Step 2: 确认 fork 入口引用存在**
  ```bash
  grep -rn "McpOptionsPage\|shortcut\|network_identity\|appearance" \
    lib/features/settings/overview/settings_page.dart
  ```
  Expected: 上述 fork 入口至少被引用。

- [ ] **Step 3: 提交**
  ```bash
  git add lib/features/settings
  git commit -m "feat(settings): keep fork MCP/shortcut/appearance on top of upstream 5.5.5"
  ```

### Task 9: 托盘通知 `lib/features/system_tray/notifier/system_tray_notifier.dart`

**Files:**
- Modify: `lib/features/system_tray/notifier/system_tray_notifier.dart`

- [ ] **Step 1: 三方合并**
  取上游通知生命周期（active state / synchronization）；保留 fork 的托盘速度布局 `tray_speed_layout.dart` 接线。

- [ ] **Step 2: 提交**
  ```bash
  git add lib/features/system_tray
  git commit -m "feat(system-tray): keep fork tray-speed layout on top of upstream 5.5.5"
  ```

### Task 10: 核心服务 `lib/hiddifycore/hiddify_core_service.dart`

**Files:**
- Modify: `lib/hiddifycore/hiddify_core_service.dart`

- [ ] **Step 1: 三方合并**
  取上游新 RPC/日志/错误映射（6 个引擎级别、重连错误处理、日志监听每次连接重新武装）；保留 fork 的节点黑名单（`blacklisted-tags`、`_loadRawOutboundTags`/`_trimTagName`）与 `releaseSystemProxy` 所需接口。

- [ ] **Step 2: 确认黑名单与 release 接口仍在**
  ```bash
  grep -n "blacklisted-tags\|_trimTagName\|releaseSystemProxy\|ReleaseSystemProxy" \
    lib/hiddifycore/hiddify_core_service.dart
  ```
  Expected: 上述符号存在。

- [ ] **Step 3: 运行 core 相关测试**
  ```bash
  ~/.puro/envs/default/flutter/bin/flutter test test/features 2>/dev/null | tail -5
  ```
  Expected: 无因该文件引起的失败。

- [ ] **Step 4: 提交**
  ```bash
  git add lib/hiddifycore/hiddify_core_service.dart
  git commit -m "feat(core): keep fork blacklist/release on top of upstream 5.5.5 RPC"
  ```

### Task 11: 构建与 CI 文件

**Files:**
- Modify: `.github/workflows/build.yml`、`Makefile`、`windows/packaging/msix/make_config.yaml`、`ios/Runner.xcodeproj/project.pbxproj`、`macos/Podfile.lock`

- [ ] **Step 1: `build.yml`**
  保留 fork 的 `dev` tag 发布（`gh` CLI 而非 `action-gh-release`）、`FLUTTER_VERSION`（与 Task 12 决定的一致）、缺凭据跳过签名；只吸收不依赖上游 secrets 的新步骤。
  ```bash
  grep -n "FLUTTER_VERSION\|gh release\|softprops\|HAS_" .github/workflows/build.yml
  ```
  Expected: 仍用 `gh` CLI 发布、`FLUTTER_VERSION` 为本机实际版本、`HAS_*` 守卫存在。

- [ ] **Step 2: `Makefile`**
  `CORE_URL`/`ANDROID_CORE_URL` 改指 `ShuttleSpace/hiddify-core`（见 Task 15）；保留 fork 的 AppImage 权限修复与本地构建配方；取上游新目标。

- [ ] **Step 3: `msix/make_config.yaml`**
  取上游新配置；保留 fork「无证书时跳过 msix」（`WINDOWS_SIGNING=false`）。

- [ ] **Step 4: `ios/Runner.xcodeproj` / `macos/Podfile.lock`**
  取上游版本；能联网时重新 `pod install` 验证，否则以上游版本为准并标注待 CI 确认。

- [ ] **Step 5: 提交**
  ```bash
  git add .github/workflows/build.yml Makefile windows/packaging/msix/make_config.yaml \
    ios/Runner.xcodeproj/project.pbxproj macos/Podfile.lock
  git commit -m "build(ci): absorb upstream build steps, keep fork dev-tag publish"
  ```

### Task 12: 依赖与锁文件

**Files:**
- Modify: `pubspec.yaml`、`pubspec.lock`（重新生成）

- [ ] **Step 1: `pubspec.yaml`**
  版本改 `version: 5.5.5+50505`；保留 fork 依赖（MCP、hotkey、`*_ohos` 系列）；取上游新增依赖与 `dependency_overrides`（`http2: ^3.1.0`、`flutter_animate: path: third_party/flutter_animate`）。

- [ ] **Step 2: 重新求解 lock**
  ```bash
  ~/.puro/envs/default/flutter/bin/flutter pub get
  ```
  Expected: 干净完成。若失败且报错指向 Dart 3.13 上界，安装 Flutter 3.44.4 到 puro 并改用其路径重跑；同时把 `build.yml` 的 `FLUTTER_VERSION` 同步为该版本。

- [ ] **Step 3: 运行 slang 与 analyze**
  ```bash
  dart run slang
  ~/.puro/envs/default/flutter/bin/flutter analyze
  ```
  Expected: slang 成功；analyze 0 error（允许 info/warning）。

- [ ] **Step 4: 提交**
  ```bash
  git add pubspec.yaml pubspec.lock
  git commit -m "chore(deps): version 5.5.5, keep fork deps, regenerate lock"
  ```

### Task 13: 行集合审计

**Files:**
- Create: `docs/merge-notes/audit_lost_lines.py`（一次性审计脚本，不进发布）

**Interfaces:**
- Consumes: 共同祖先 `f26aadb3`、上游 `v5.5.5`、合并结果 `merge/v5.5.5`
- Produces: 上游新增却丢失的行清单

- [ ] **Step 1: 写审计脚本**
  ```python
  # docs/merge-notes/audit_lost_lines.py
  import git  # 或 subprocess 调 git
  base, up, merged = "f26aadb3", "v5.5.5", "merge/v5.5.5"
  files = subprocess.check_output(
      ["git","diff","--name-only",base,up]).decode().split()
  for f in files:
      try:
          up_text   = subprocess.check_output(["git","show",f"{up}:{f}"]).decode()
          base_text = subprocess.check_output(["git","show",f"{base}:{f}"]).decode()
          merged_text = subprocess.check_output(["git","show",f"{merged}:{f}"]).decode()
      except subprocess.CalledProcessError:
          continue
      up_add = set(up_text.splitlines()) - set(base_text.splitlines())
      merged_lines = set(merged_text.splitlines())
      lost = [l for l in up_add if l.strip() and l.strip() not in merged_lines]
      if lost:
          print(f"# {f}: {len(lost)} 行可能丢失")
          for l in lost[:50]:
              print("   ", l[:120])
  ```

- [ ] **Step 2: 运行审计**
  ```bash
  python3 docs/merge-notes/audit_lost_lines.py
  ```
  Expected: 输出每文件中上游新增且合并结果里不存在的、非空白行；与 `git diff` 移动/重排产生的假阳性区分后，逐条判断——要么是上游与 fork 同义重写（可接受），要么必须补回（bug）。

- [ ] **Step 3: 把审计结果写进合并记录**
  在 `docs/merge-notes/2026-11-XX-upstream-5.5.5.md` 记录「丢失 0 行 / 有意替换 N 行 / 补回 M 行」，并附被替换行的清单。

### Task 14: 子模块 core 源码合并

**Files:**
- Submodule: `hiddify-core`（在其仓库内工作）、`hiddify-core/hiddify-sing-box`

- [ ] **Step 1: 在 core 仓库开合并分支**
  ```bash
  cd hiddify-core
  git fetch origin hiddify-upstream 2>/dev/null || git fetch origin
  git checkout -b merge/upstream-5.5.5 737f287
  ```

- [ ] **Step 2: 合入 core dev 线独有修复**
  ```bash
  git merge 73225d0 --no-commit   # 或 cherry-pick 16a16df、9840cfc
  ```
  Expected: 系统代理实现等价；若有冲突，确认两份实现一致后取其一。

- [ ] **Step 3: 合到上游 `ad83d757`**
  ```bash
  git merge ad83d757 --no-ff
  ```
  Expected: 解决冲突（重点是 `v2/hcore/*`、`commands.go`、sing-box 指针）。

- [ ] **Step 4: 合并 sing-box 两条修复线**
  进入 `hiddify-sing-box`：把 fork `a799eff4` 与 `656b78d` 合到上游新指针。

- [ ] **Step 5: 推送 fork**
  ```bash
  git push origin merge/upstream-5.5.5
  cd hiddify-sing-box && git push origin <合并分支>
  ```
  Expected: `ShuttleSpace/hiddify-core`、`ShuttleSpace/hiddify-sing-box` 出现合并分支。

- [ ] **Step 6: 在 app 更新子模块指针**
  回到 app 仓库：
  ```bash
  git -C hiddify-core checkout <合并后的 commit>
  git add hiddify-core
  git commit -m "chore(core): merge fork system-proxy onto upstream 5.5.5"
  ```

### Task 15: core 发布与引用

**Files:**
- Modify: `Makefile`、`dependencies.properties`

- [ ] **Step 1: 在 `ShuttleSpace/hiddify-core` 打 tag 并触发 Release**
  ```bash
  cd hiddify-core
  git tag v5.5.5 && git push origin v5.5.5
  git tag dev  -f && git push origin refs/tags/dev -f   # 滚动 draft
  ```
  Expected: Release workflow 产出 `hiddify-lib-*` 与 Android 包。

- [ ] **Step 2: 改 `Makefile` 下载地址**
  `CORE_URL`/`ANDROID_CORE_URL` 从 `hiddify/hiddify-core` 改为 `ShuttleSpace/hiddify-core`（两个 channel 分支都改）。

- [ ] **Step 3: 改 `dependencies.properties`**
  `core.version=5.5.5`。

- [ ] **Step 4: 验证能从 fork release 下载**
  ```bash
  curl -I https://github.com/ShuttleSpace/hiddify-core/releases/download/v5.5.5/hiddify-core-linux-amd64.tar.gz
  ```
  Expected: HTTP 200。若本机 github HTTPS 不可达，改为在 CI runner 上确认。

- [ ] **Step 5: 处理 `ANDROID_CORE_VERSION=5.0.0`**
  先试上游 5.5.5 的 AAR 能否让 Android Kotlin 编译；能则删掉这行钉法，不能则改为 `5.5.5` 并在合并记录写明原因。

- [ ] **Step 6: 提交**
  ```bash
  git add Makefile dependencies.properties
  git commit -m "build(core): download fork core 5.5.5 from ShuttleSpace releases"
  ```

### Task 16: 并入鸿蒙分支

**Files:**
- Merge: `feat/ohos-support` 进 `merge/v5.5.5`

- [ ] **Step 1: 合入鸿蒙分支**
  ```bash
  git checkout merge/v5.5.5
  git merge --no-ff refs/heads/feat/ohos-support
  ```
  Expected: 冲突集中在 `pubspec.yaml`/`pubspec.lock`、`.gitignore`、`lib/bootstrap.dart`、`macos/Podfile.lock`、`Makefile`、`msix/make_config.yaml`；逐项解，鸿蒙依赖与插件实现全保留。

- [ ] **Step 2: 解决 `pubspec.yaml`/`pubspec.lock` 冲突**
  保留 Task 12 的 `5.5.5+50505` 与上游改动，再叠加鸿蒙 `*_ohos` 依赖与 `dependency_overrides`（`flutter_secure_storage_platform_interface: ^2.1.1`、`flutter_secure_storage_windows: 4.1.0`、`win32: ^5.12.0`）。
  ```bash
  ~/.puro/envs/default/flutter/bin/flutter pub get
  ```
  Expected: 能解析 ohos 依赖（从 pub.flutter-io.cn）。

- [ ] **Step 3: 提交**
  ```bash
  git add -A   # 仅 ohos 相关与解冲突的已跟踪文件，勿加 .workbuddy/、ohos 构建产物
  git commit -m "feat(ohos): merge HarmonyOS support onto 5.5.5"
  ```

---

## 验证阶段

### Task 17: 鸿蒙依赖与 Dart 层检查（不出包）

**Files:** 无新增；仅验证

- [ ] **Step 1: `flutter pub get` 含 ohos 依赖**
  Expected: 完成，无解析失败。

- [ ] **Step 2: `flutter analyze` 不因鸿蒙接入报错**
  ```bash
  ~/.puro/envs/default/flutter/bin/flutter analyze
  ```
  Expected: 0 error。

- [ ] **Step 3: 在合并记录标注鸿蒙出包验证后置**
  写明本机 puro `ohos` 环境 `Wrong full snapshot version` 缺陷，列为遗留。

### Task 18: 功能回归与 release 包

**Files:** 无新增；仅验证

- [ ] **Step 1: 全量测试**
  ```bash
  ~/.puro/envs/default/flutter/bin/flutter test
  ```
  Expected: 全部通过（与历史基线 269 项左右一致）。

- [ ] **Step 2: fork 功能冒烟清单**
  逐项确认入口仍在且可触发：节点搜索、节点黑名单、per-app 路由、流量历史/托盘速度、全局快捷键、备份导出导入、自定义代理、通知、MCP 设置页、系统代理释放。

- [ ] **Step 3: release 包验证**
  ```bash
  just android      # 或 make android-release；从 ShuttleSpace core 下载
  ```
  Expected: `build/app/outputs/flutter-apk/app-release.apk`（无 keystore 时 debug 签名）；装机能过闪屏、首页/设置可渲染、能连接。macOS 能构建并启动一次。

- [ ] **Step 4: core 产物/RPC 检查**
  在 macOS 上连接后断开或切模式，确认系统代理释放（对应 fork 功能）；或在日志里确认 `SetSystemProxyEnabled` 调用成功。

### Task 19: CI 与回写 `dev`

**Files:**
- Modify: `.github/workflows/ci.yml`（临时把 `merge/v5.5.5` 加进 push 分支）
- Modify: `dev`

- [ ] **Step 1: 临时给集成分支加 CI 触发**
  ```bash
  git checkout merge/v5.5.5
  # 在 ci.yml 的 push.branches 加 merge/v5.5.5
  git add .github/workflows/ci.yml
  git commit -m "ci: allow merge/v5.5.5 to run CI"
  git push origin refs/heads/merge/v5.5.5
  ```
  Expected: CI 跑 `test` + 四条 build 腿；全绿。

- [ ] **Step 2: 落回 `dev`**
  ```bash
  git checkout dev
  git merge --ff-only merge/v5.5.5
  git push origin refs/heads/dev
  ```
  Expected: 滚动 release 重新产出 dev 资产；CI 再绿一次。

- [ ] **Step 3: 决定是否保留 `merge/**` 触发**
  若不再需要，从 `dev` 的 `ci.yml` 删掉临时分支条目并提交；若保留，确保不影响其它分支。

### Task 20: 回滚锚点与交付物

**Files:**
- Create: `docs/merge-notes/2026-11-XX-upstream-5.5.5.md`

- [ ] **Step 1: 写合并记录**
  含：拓扑、冲突逐项结论、行集合审计结果、被有意替换的上游代码、子模块/core 指针、core 发布来源、验证记录、遗留（鸿蒙出包、core 二进制来源确认）。

- [ ] **Step 2: 更新分支模型文档**
  若本轮确认了新的子模块 URL 与 core 发布规则，更新 `docs/branching-and-release.md`。

- [ ] **Step 3: 回滚说明**
  在合并记录写明：出问题 `git checkout dev && git reset --hard pre-merge-5.5.5`（tag），`dev` 在验证前未动，锚点仍在。

- [ ] **Step 4: 提交与推送文档**
  ```bash
  git add docs/merge-notes docs/branching-and-release.md
  git commit -m "docs(merge): record upstream 5.5.5 integration"
  git push origin refs/heads/dev
  ```

---

## Self-Review 摘要

- **Spec 覆盖**：基线/快进（T1）、逐文件冲突（T3–T12）、行集合审计（T13）、core 源码与发布（T14–T15）、鸿蒙（T16–T17）、验证门槛（T18–T19）、交付物（T20）均有对应任务。
- **步骤粒度**：每个冲突文件一个 Task，含「三方合并 → 确认 fork 入口仍在 → 测试/analyze → 提交」；可独立审查。
- **类型一致性**：`releaseSystemProxy` / `SetSystemProxyEnabled` / `blacklisted-tags` 在 T6、T10、T18 反复引用同一符号名。
- **Review Focus**：5 条输入类/失败模式已填入顶部，并各自落到 T13 / T4–T6,T8,T18 / T15,T18 / T3 / T12,T19。
- **比例**：计划以流程与约束为主，未转写函数体（合并冲突解法由实现者按三方合并现场决定）。
