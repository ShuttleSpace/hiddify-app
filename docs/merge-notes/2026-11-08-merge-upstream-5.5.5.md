# Merge note — sync fork `dev` onto upstream `hiddify-app` `main` (5.5.5)

- **Date:** 2026-11-08
- **Upstream tip merged:** `0d6eb882` (`hiddify/hiddify-app` main, version `5.5.5+50505`, `core.version=5.5.5`)
- **Fork branch landed on:** `main-plus-dev` (then fast-forward / rebase into `dev`)
- **Fork version set:** `5.5.5+50506` (`msix_version` `5.5.5.0`, iOS `50506` / `5.5.5`)
- **Remote rule:** only `ShuttleSpace/hiddify-app` is pushed. `main` is kept a fast-forward-only mirror of upstream and was **not** pushed (pushing it would trigger CI that clears the fork's draft release).

---

## 0. One-line summary

`dev` (fork, ~191 commits ahead of the old base) was merged into `main-plus-dev`
(started from upstream `0d6eb882`, 278 commits ahead of the old base). This is a
**real divergent merge**, not the empty fast-forward of the 2026-10-19 catch-up:
upstream rewrote ~12 core Dart files (≈1200 lines of new features — crash
reporting, daily update check, phone import, connection health, IP-based proxy
speed test, gRPC stream-cancellation fixes) and bumped `core.version` 4.1.0 →
5.5.5.

This commit establishes a **compiling, analyze-clean base on the upstream 5.5.5
tree**. Fork increments that lived *inside* the 12 core files upstream rewrote
are dropped in this commit and are listed as re-plant work below — they are **not
silently gone**, the support code (models, providers, tests, MCP, release-notes
page, `hiddifyctl`) is intact and the files are ready to be re-planted.

---

## 1. Resolved in this commit

### Version / build alignment (✅ matches "core.version 一致" + fork suffix)
- `pubspec.yaml` version `5.5.5+50506` (build number kept an integer so Android
  `versionCode.toInteger()` and `change_version.sh` still work).
- `windows/packaging/msix/make_config.yaml` `msix_version: 5.5.5.0` (kept fork's
  `identity_name: Hiddify.HiddifyNext` so the fork's Windows package id is distinct
  from upstream's).
- `ios/Runner.xcodeproj/project.pbxproj` `CURRENT_PROJECT_VERSION = 50506`,
  `MARKETING_VERSION = 5.5.5` (kept `CODE_SIGN_STYLE = Automatic` — the fork's CI
  has no Apple cert).
- Fixed a duplicated `dependency_overrides` block that the 3-way merge produced
  (`simple_icons`/`tray_manager` + upstream's `http2`/`flutter_animate` are now in
  one block).

### `dependencies.properties`
- `core.version=5.5.5` (was 4.1.0). **Note:** this is a hard jump. The app's gRPC
  stub already carries 30 RPCs and matches upstream 5.5.5 (verified —
  `lib/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart` is tracked and
  identical to upstream's 30-RPC version), so no proto regeneration was needed.
  The Android AAR pin (`ANDROID_CORE_VERSION=5.0.0`) from the v5.1.0 CI fix is
  **overridden by this** — `Makefile` now reads `core.version` for Android too.

### Translations (11 files, union)
- Recursively merged with upstream as the structural base, then re-dumped with the
  upstream 2-space indent (so the diff vs upstream only shows fork keys, not 1400
  lines of whitespace). ICU plural/rich-text keys (`bulkSuccess(plural,
  param=count)`, `(map)` keys) preserved; fork's intentional `inbound.lanSharing =
  "VPN sharing"` kept; 6 upstream-upgraded values applied.

### CI / config
- `Makefile`: kept the fork's `WINDOWS_SIGNING=false` msix-skip guard **and**
  upstream's `WINDOWS_SIGN_BACKEND` signing hook.
- `build.yml`: **kept the fork's verified CI** (the upstream 5.5.5 rewrite adds
  Azure signing / TestFlight / VirusTotal / Google-Play jobs that the fork cannot
  run without upstream's secrets). Recorded here so it isn't mistaken for a loss.
- `ios/project.pbxproj`: version + signing resolved as above.

### Compile fixes (so the 5.5.5 tree builds with the fork's environment)
- **slang naming:** upstream references CamelCase internal translation class names
  (`TranslationsConnectionHealthEn`) but the fork's `slang.yaml` (CLI codegen,
  deliberately not `build_runner`/`slang_build_runner`) emits `$`-separated names
  (`Translations$connection$health$en`). Pinning slang to 4.8.1 to match upstream
  is rejected — the mirror `pub.flutter-io.cn` lacks `slang_flutter 4.8.0`. Instead
  the single upstream reference (`connection_button.dart:182`) was adapted to the
  `$`-style type. `slang` stays at fork's `^4.19.0`.
- `all_proxies_overview_provider.dart`: the fork's `watchAllGroups()` is gone from
  the upstream `ProxyRepository`; rewired to `watchActiveProxies()` returning
  `OutboundGroupList` and extracting `.items`. Matching test updated.
- `mcp_server.dart`: `ConnectionStatus.when` now covers upstream's new
  `waiting` / `noAvailableProxies` / `hotReloading` states.

### Verification
- `flutter analyze`: **0 errors** (91 info-level lint hints, pre-existing).
- `flutter test`: **416 / 417 pass**. The one failure is the desktop mTLS smoke
  test (see §3).
- `tools/hiddifyctl`: `go build ./...` and `go vet ./...` clean.
- `flutter pub get` / `flutter pub run slang` / `flutter pub run build_runner` all
  regenerate cleanly.

---

## 2. Fork increments dropped (re-plant backlog) — NOT silently removed

The 12 core files upstream rewrote were taken at their **upstream 5.5.5** content
(the merge's conflicting regions, plus the non-conflicting fork additions inside
those same files, were discarded when the file was set to upstream). The fork
*support* files (models, providers, tests, the MCP server, the release-notes page,
`hiddifyctl`) are untouched and compile. What must be re-planted onto the new
structures, file by file:

| File (upstream-rewritten) | Fork feature that must be re-planted |
|---|---|
| `lib/features/app/widget/app.dart` | fork's release-notes entry / any bootstrap additions |
| `lib/features/connection/data/connection_repository.dart` | fork connection-health / hot-reload data wiring |
| `lib/features/connection/notifier/connection_notifier.dart` | fork connection-health state |
| `lib/features/profile/add/add_profile_modal.dart` | fork custom-proxy tab |
| `lib/features/profile/details/profile_details_notifier.dart` | fork config-tags / JSON-edit increments |
| `lib/features/profile/details/profile_details_page.dart` | fork detail-page increments |
| `lib/features/proxy/data/proxy_repository.dart` | fork `watchAllGroups()` (superseded by `watchActiveProxies`) |
| `lib/features/proxy/overview/proxies_overview_page.dart` | fork **node search** UI |
| `lib/features/proxy/widget/proxy_tile.dart` | fork **blacklist** UI |
| `lib/features/settings/overview/settings_page.dart` | fork **settings search** |
| `lib/features/system_tray/notifier/system_tray_notifier.dart` | fork **tray speed** badge |
| `lib/hiddifycore/hiddify_core_service.dart` | fork mTLS / gRPC-stream increments |

Each of these is a separate re-plant pass: understand the upstream 5.5.5 structure,
re-apply the fork behavior, rebuild, and run the affected tests. GUI / real-device
verification is required for each (the agent cannot substitute for that).

---

## 3. Known issues / not-yet-done

- **Desktop mTLS smoke test fails locally** (`mtls_desktop_smoke_test.dart`): it
  launches the native core library `hiddify-core/hiddify-core.{so,dylib,dll}`. The
  on-disk library was built before this merge switched the submodule to 5.5.5, so
  the app (now 5.5.5) and the native lib handshake mismatch on a cert parse
  (`FormatException: Unexpected extension byte`). This is an **environment / native
  build** concern, not a Dart regression — the current `hiddify_core_service.dart`
  is byte-identical to upstream and the test is upstream's own. Rebuild the native
  library from the 5.5.5 submodule (CI does this for desktop artifacts) before
  trusting that test.

- **`hiddify-core` fork fixes:** the fork's `hiddify-core` submodule was 3 commits
  ahead of the old base. `e5ba924` (CI: stop sing-box version step recursing into
  submodules) cherry-picks cleanly and is parked on the submodule branch
  `main-plus-dev-core`. `a816c7d` (**implement `SetSystemProxyEnabled`** so leaving
  system-proxy mode releases the macOS OS proxy) is **blocked**: it calls
  `settings.ReleaseSystemProxy()`, which 5.5.5's `sing-box` no longer has — upstream
  refactored `proxy_darwin.go` into an inbound-owned instance model that the fork
  explicitly worked around. Re-planting it requires porting fork's global proxy
  registry (`release_proxy_darwin.go`) onto 5.5.5's `sing-box`, a separate Go /
  macOS round. `737f287` (sing-box pointer) is incompatible with 5.5.5 core and is
  dropped. **The app's submodule pointer is therefore upstream 5.5.5 (`ad83d75`)
  for this round.**

- **GUI / real-device:** not yet verified by the user. The agent cannot substitute
  for visual / network-round-trip acceptance.

---

## 4. What to do next (in order)

1. Re-plant the backlog in §2, one file per pass, each with `flutter analyze` +
   the affected tests + GUI check.
2. Resolve the macOS system-proxy release port (§3, `a816c7d`) on a fork
   `hiddify-core` branch and push it; then update the app's submodule pointer.
3. Rebuild the native core library from 5.5.5 and re-run the mTLS smoke test.
4. Real-device + desktop GUI acceptance.
5. Only after all of the above: rebase `dev` onto `main-plus-dev`, push
   `ShuttleSpace/hiddify-app` `dev`, and (if releasing) build `v5.5.5`.
