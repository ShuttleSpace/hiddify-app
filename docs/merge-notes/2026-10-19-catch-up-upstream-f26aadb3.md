# Merge note — 追上游：把 fork 的 `main` 快进到 `f26aadb3`，并把丢掉的上游内容补回

- **日期**：2026-10-19
- **上游 tip**：`f26aadb3`（`hiddify/hiddify-app` 的 main）
- **落点**：`main-plus-dev` → `dev`，提交 `0e6a983c` / `cf8b0e6f` / `a49120ac`
- **远程**：只推 `ShuttleSpace/hiddify-app`

---

## 0. 一句话

`main` 快进了 269 个提交到上游 tip；但真正的工作不在快进上——**那 269 个提交早就在 `dev` 的历史里了**，
问题出在上一轮合并把**每个冲突都判给了 fork**，于是在 12 个文件里静默丢掉了上游的新代码。

---

## 1. `main` 的快进

```bash
git remote add upstream https://github.com/hiddify/hiddify-app.git
git fetch upstream main
git checkout main && git merge --ff-only upstream/main   # 276a7eff → f26aadb3，269 个提交
git push origin main:main
```

快进后 `git diff upstream/main main` 为空——`main` 与上游**逐字节一致**。
`main` 上跑出来的 CI 是红的（macOS 缺 Apple 签名密钥、`update-draft` 用的是上游那套 action），
这是上游 workflow 自己的前提，`main` 按规则保持上游干净，不去改它。

---

## 2. 关键发现：`dev` 早就有上游那 269 个提交

```
f26aadb3 是 dev 的祖先 → 是
f26aadb3 是 main-plus-dev 的祖先 → 是
```

也就是说 `git merge main dev` 是**空操作**。上游的内容是在上一轮那次大合并里进来的。

但那次合并的解法是「57 个冲突**全部**判给 `main-plus-dev`（fork 侧）」，
最后靠 `git read-tree --reset -u main-plus-dev` 把整棵树直接置成 fork 侧。
后果：**凡是上游在这 269 个提交里改过、而 fork 也改过的文件，冲突的那些 hunk 留下了 fork 的旧版本**。

---

## 3. 怎么量出「到底丢了什么」

不能靠看 diff 大小（代码挪个位置就算「变了」）。用行集合比对：

```python
# 上游新增的行 ∩ dev 文件里完全不存在的行 = 真正丢掉的内容
up_add = 上游 276a7eff→f26aadb3 新增的行
dev_lines = dev 文件里所有行
lost = [l for l in up_add if l.strip() not in dev_lines]
```

两边都改过的文件有 44 个，其中 12 个真有丢失，合计 **179 行**：

| 文件 | 丢的行 | 性质 |
|---|---|---|
| `lib/core/notification/in_app_notification_controller.dart` | 78 | **真缺口**：上游把通知系统重写成 SnackBar |
| `lib/hiddifycore/hiddify_core_service.dart` | 45 | **真缺口**：热重载、Windows 报错映射、引擎日志 |
| `lib/features/app_based_routing/overview/app_list_page.dart` | 21 | 有意替换（installed_apps → 自家 metadata provider） |
| `lib/features/connection/notifier/connection_notifier.dart` | 19 | **真缺口**：连接前先读 ref、失败按 error 记 |
| `lib/features/connection/data/connection_repository.dart` | 4 | **真缺口**：重连改热重载 |
| `lib/core/db/db.dart` | 1 | 有意：dev 的 schema 已经是 9 |
| `lib/features/app_based_routing/model/app_package_info.dart` | 1 | 有意：fork 改过构造函数 |
| `lib/features/app/widget/app.dart` | 3 | **真缺口**：`scaffoldMessengerKey` + `SnackBarHost` 接线 |
| `pubspec.yaml` | 1 | **真缺口**：`archive` 没被直接声明 |
| `lib/features/about/widget/about_page.dart` | 2 | 不用改：方法改成返回 void 后两种写法都合法 |
| `test/features/profile/data/profile_repository_test.dart` | 3 | 有意：fork 的测试辅助类 |
| `test/features/proxy/proxies_overview_notifier_test.dart` | 1 | **真缺口**：fake 还在返回 `ToastificationItem` |

**这一列表本身就是最有用的产出**：它把「上游有什么、fork 有什么」变成可核对的清单。

---

## 4. 补回的方式

### 4.1 通知系统：取上游的 SnackBar 实现，保留 fork 的两个参数

上游用 `ScaffoldMessenger` + `SnackBarHost`（套在 Navigator 外面，toast 才不会被弹窗/底部面板盖住），
替掉了 `toastification`；关闭计时器只在指针移开时才走。

fork 的版本多两个参数，两处调用点要用：

- `duration` —— macOS 断开后的 shell 代理提示要停 10 秒
- `replaceExisting: false` —— 同一事件的两条提示要都留着

**取上游的实现，把这两个参数接回去**：

```dart
void showInfoToast(String message, {ToastAction? action, Duration? duration, bool replaceExisting = true}) =>
    _show(message, action: action, duration: duration, replaceExisting: replaceExisting);
```

`replaceExisting: false` 在 SnackBar 下的行为和 toastification 不同：SnackBar 不会同屏叠放，
第二条要等第一条收起才出现。参数保留住了原意，实际观感略变。

上游的「bootstrap 期间没有 messenger 就吞掉」本来就是 fork 那层 try/catch 的等价物——
上游用 `appScaffoldMessengerKey.currentState == null` 判断，更干净。

### 4.2 `app.dart`：把接线接回去

```dart
MaterialApp.router(
  scaffoldMessengerKey: appScaffoldMessengerKey,   // 上游加的
  ...
  builder: (context, child) {
    child = SnackBarHost(child: UpgradeAlert(...));   // 上游加的
  },
)
```

fork 的外观种子色（`AppearanceOptions.colorSource` / `seedColor`）和两个 `ref.listen`
（黑名单 guard、流量记录器）**原样保留**。

### 4.3 `hiddify_core_service.dart`：上游的结构 + fork 的黑名单

这个文件两边都改得很多（上游 588 行 / fork 692 行），手工合容易漏。
用 `git merge-file` 做三方合并（上游版 / 共同祖先 / fork 版），只剩 5 处冲突，逐处判断：

| 冲突 | 解法 |
|---|---|
| import 区 ×2 | 两边都留 |
| `reload()` vs `releaseSystemProxy()` | 两个方法都留（上游的热重载 + fork 的 macOS 代理释放） |
| Stream error 的写法 | 取上游的 `loggy.error(...)` |
| `getLogLevel` 返回类型 | 取上游的 `logging.Level` |

合并后**上游的关键能力全部到位**：

- `reload()`：先热重载，核心不支持时才重启 —— 之前 fork 的重连是直接 `restart()`，改个设置就断隧道
- Windows 报错映射：`missingPrivilege()`（TUN 需要提权）、`tunAddressInUse()`（TUN 地址被占）
  不再一律报 "unexpected"
- 引擎日志走 `coreLogFor(event.type).log(getLogLevel(event.level), ...)`，六个引擎级别对六个日志级别
- 每次连接都重新武装日志监听（监听只在启动时装一次，扛不过引擎重启）
- `logController`（300 条缓冲）和 `logBuffer` 成了死代码，随上游一起删

**fork 的节点黑名单保留**：`changeOptions` 里塞 `blacklisted-tags` 的那段，以及
`_loadRawOutboundTags` / `_trimTagName`。

### 4.4 `connection_notifier.dart` / `connection_repository.dart`

- notifier：取上游的「连接前先读 ref」（失败的连接会发 core restart 信号，
  debug 构建在那之前拒绝任何 ref 调用）、提前置 `Connecting`、失败按 `error` 级别记日志；
  fork 的 shell 代理提示原样保留。合并后**两处 `restoreConnectionOnStartup` 重复定义**
  （fork 早就搬过上游这版），删掉重复的那份。
- repository：重连改成 `singbox.reload(...)`（上游），`watchHotReloading` 的注释取上游措辞。

### 4.5 `pubspec.yaml`

| 改动 | 原因 |
|---|---|
| `loggy: ^2.0.3` → `logging: ^1.3.0` | `loggy` 现在只是 `lib/utils/custom_loggers.dart` 里的**本地 shim**，直接依赖的是 `package:logging` |
| 加 `archive: ^4.0.4` | `lib/utils/text_utils.dart` 直接 import 它，之前只是传递依赖 |
| 去掉 `toastification: ^2.3.0` | 通知系统改成 SnackBar 后不再用 |
| `flutter_test` 取消注释 | 上游的做法 |
| `version: 4.1.4+40104` → `5.0.0+50000` | 应用现在是「上游 5.0 + fork 的 app 层」；而且**同包名 `app.hiddify.com` 下 versionCode 必须涨**，否则装不上 |

> `loggy` 和 `toastification` 从依赖图里彻底消失（`flutter pub get` 确认）。

---

## 5. 验证

```
flutter analyze  →  0 error（69 issues，全是 info/warning）
flutter test     →  All tests passed!  (269)
```

CI run `39268331724`（`dev`，`a49120ac`）：`test` + 四个平台的 build 腿 + `update-draft` 全绿，
`draft` release 拿回 11 个包。

本地 `just macos` 出 release 包并启动一次：

```
---- run started 2026-10-19T22:47:03  ·  Hiddify v5.0.0 (50000) [dev]
```

- 版本号生效（`5.0.0 (50000)`）
- 首页完整渲染，隧道**已连接**（87 ms）—— 合并后的 core service 正常
- 日志里**没有** `app.uncaught`。旧构建有 `PlatformDispatcherError: Null check operator used on a null value`
  （drift schema 撞车），这次没有了
- 日志里剩下的 ERROR 都**是既有问题**：旧日志里同样的 `startListeningStatus` 有 121 处、
  `system tray` 有 5 处，这次分别是 7 处和 1 处

> `app.log` 只记 error 是上游的设计（`5acc1f35 feat(logging): keep only errors in the app log file`，
> 早于本轮）。旧日志里那些 INFO 行是更早的构建用旧 logger 写的。

**仍需用户复验**：通知系统换了实现（toastification → SnackBar），外观和交互有变化，
这是本轮唯一用户可见的行为改变。

---

## 6. 这轮踩到的坑

### 6.1 「冲突全判给 fork」会静默丢上游的重构

上一轮 57 个冲突全按 fork 侧解，看起来干净、编译也过、设备也验过，
但**上游 179 行新代码就这么没了**——而且丢的不是琐碎代码，是通知系统重写、热重载、Windows 报错映射。

**规则**：合并后必须逐文件核对「上游新增的行是否还在」，不能只看「能不能编过」。

### 6.2 判断「上游丢了什么」不要看 diff，要看行集合

见 §3。代码挪位置会让 diff 爆炸，行集合比对能剔掉假阳性。

### 6.3 三方合并用 `git merge-file`，别手抄

```bash
git show <upstream>:<file> > /tmp/cur.dart
git show <base>:<file>    > /tmp/base.dart
git show <fork>:<file>    > /tmp/other.dart
git merge-file --diff3 -L upstream -L base -L fork /tmp/cur.dart /tmp/base.dart /tmp/other.dart
```

冲突数会小到能一个个判断。`--diff3` 会把共同祖先一起打出来，判断「这处该谁赢」时非常有用。

### 6.4 `main` 的 CI 会清空 `draft` release

`ci.yml` 对 `main` 和 `dev` 都触发。`main` 用的是**上游那套** `update-draft`：
`Delete Current Release Assets` 排在 `Create or Update Draft Release` **之前**，
而上游的 action 在 fork 上必然 403 —— 于是**先删掉资产、再失败**。

所以每次同步上游 `main` 之后，`draft` release 会被清空，直到 `dev` 的 CI 跑完重新发布。

- 每次 run 的 Actions artifact（保留 30 天）不受影响
- `dev` 的 CI 跑完会把 11 个包重新发布回 `draft`
- 想根治：让 `dev` 发布到自己的 tag（要连带处理 `upload-release` 和 `upload-to-testflight`，
  它们靠 `tag-name != 'draft'` 才跳过）——本次没做，记在这里

### 6.5 上游删掉的代码不等于要保留

上游在 269 个提交里删掉了连接成功时的强震动反馈（`hapticServiceProvider.heavyImpact()`）。
那是上游自己的 UX 决策，不是冲突，按「取上游结构」处理。
判断依据是三方比对：旧上游有、上游新版本没有、fork 保留 → 跟上游。

---

## 7. 遗留

1. `draft` release 与上游 `main` 的 CI 抢同一个发布位（见 §6.4），本次未根治
2. `upload-release` job 仍用 `softprops/action-gh-release`，将来打正式 tag 会撞同一个 403
3. `main` 的 CI 在 fork 上必然红（缺上游的签名密钥），这是上游 workflow 的前提，不是 fork 的问题
4. fork 的 `main` 这次才第一次跟上上游；以后同步上游要走
   「fetch → ff 到 `main` → 逐文件补回上游被丢的内容 → 落到 `dev`」这套流程
