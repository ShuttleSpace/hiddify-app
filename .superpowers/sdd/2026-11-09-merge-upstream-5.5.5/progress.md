# SDD ledger — plan: docs/superpowers/plans/2026-11-09-merge-upstream-5.5.5.md

Task 0: complete — refs captured; pre-merge-5.5.5 tag created (local); flutter 3.47.2; PUB_HOSTED_URL=pub.flutter-io.cn. Tag not yet pushed (shared side-effect deferred).

Task 1: main fast-forwarded to v5.5.5 (7804cada) and pushed to origin. main now upstream-pure mirror of v5.5.5 (3 commits behind hiddify-upstream/main tip, expected: target is v5.5.5).

## Integration conflict resolution (Task 2-12), inline
- Staged clean: app.dart, connection_repository, connection_notifier, add_profile_modal, profile_details_notifier, profile_details_page, settings_page, system_tray_notifier, hiddify_core_service, proxy_repository.
- proxy_repository: interface union — watchActiveProxies->OutboundGroupList (upstream) + watchAllGroups->List<OutboundGroup> (fork) + getCurrentIpInfo(customIpInfoUrl) (upstream). Impl already matched.
- connection_repository: kept upstream HotReloading status + service-mode reconnect + changeOptions error-match; re-added fork releaseSystemProxy() and profileId arg to changeOptions. Removed dup @override.
- connection_notifier: import union; kept fork serviceMode listen + coreRestartSignal watch + wasSystemProxy/_releaseSystemProxy; kept upstream epoch guard + Disconnecting-on-tap.
- profile_details_notifier: took upstream Isolate.run(_editableConfig) (supersedes fork inline JSON parse). profile_details_page: upstream Expanded/switch(data.config) + fork editorKey. add_profile_modal: import union (phone_import + custom_proxy).
- settings_page: kept fork search TextField + grouped results; upstream SettingsSection list retained below (need to re-verify fork MCP/shortcut entries present).
- system_tray_notifier: import union; kept upstream badge-first flow + fork _refreshTraySpeedIndicator/traySpeedLayout; dropped fork _modifyConnectionStatus (upstream badge supersedes).
- hiddify_core_service: kept upstream OutboundGroupList/_stopRequests/_statusListener + fork lastBlacklistedTags; changeOptions kept upstream managesLifecycle early-return THEN fork blacklist optionsJson path.
- proxy_tile: constructor union (testable/showPing + highlight/disabled/blacklistReason). Build = upstream new tile (FlagSlot/ping styles/speed chips) wrapped in fork AnimatedContainer blacklist highlight; disabled->block icon + faded; blacklistReason appended to subtitle suffix.
- proxies_overview_page: body = fork Column(search field + allGroupsError + Expanded Stack) wrapping upstream CustomScrollView(SliverGrid/SliverList toggle + KeepTopFooter + bottom padding) with blacklist-aware tileBuilder(testable/showPing=!blacklisted, onTap guard+toast, Tooltip); search overlay on top. FAB = upstream speed-test + urlTest(displayedGroup?.tag??select), added heroTag url-test. crossAxisCountForWidth 268->420 (upstream tuning for new wider tile; keeps _scrollToNode consistent).
- NOTE: activeProxyGroupNotifierProvider is write-only in fork dev too (.select never read to filter display) — preserved as-is, not "fixed".

## Toolchain decision (realized)
- Local default is Flutter 3.47.2 / Dart 3.13.2. build_runner 2.4.15 + riverpod_generator deadlocks on Dart 3.13.2 (two 10-40min runs froze at ~284/300). ohos lock requires dart <3.13.0-z. CI pins 3.44.4.
- puro create failed (github HTTPS + gitee EOF), so built env manually: git worktree of ~/.puro/shared/flutter at tag 3.44.4 -> ~/.puro/envs/flutter3444/flutter; `flutter --version` downloaded engine a10d8ac from mirror. Now Flutter 3.44.4 / Dart 3.12.2.
- ALL subsequent pub get / slang / build_runner / analyze / test use ~/.puro/envs/flutter3444/flutter/bin/flutter. build.yml FLUTTER_VERSION stays 3.44.4 (fork value) — correct.

## Remaining conflicts status
- All 32 app-level conflicts resolved EXCEPT hiddify-core submodule pointer (U). Staged the rest.
- HISTORY.md has literal SEARCH/REPLACE text (documentation, not a git conflict) — left as-is.
