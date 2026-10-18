import 'dart:async';
import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/data/node_blacklist_engine.dart';
import 'package:hiddify/features/proxy/domain/proxy_search.dart';
import 'package:hiddify/features/proxy/model/proxy_search_result.dart';
import 'package:hiddify/features/proxy/notifier/active_proxy_group_notifier.dart';
import 'package:hiddify/features/proxy/notifier/node_blacklist_controller.dart';
import 'package:hiddify/features/proxy/overview/all_proxies_overview_provider.dart';
import 'package:hiddify/features/proxy/keep_top/keep_top_widgets.dart';
import 'package:hiddify/features/proxy/model/proxy_entity.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_search_overlay.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxiesOverviewPage extends HookConsumerWidget with PresLogger {
  const ProxiesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    final gridLayout = useState(true);
    final searchQuery = useState('');
    final searchController = useMemoized(TextEditingController.new);
    // ignore: no_leading_underscores_for_local_identifiers
    final _highlightedNode = useState<String?>(null);
    final pendingSearchTarget = useState<ProxySearchResult?>(null);
    final didAutoLocate = useState(false);
    final scrollController = useScrollController();

    final groups = ref.watch(allProxiesOverviewProvider).valueOrNull ?? const [];
    final allGroupsError = ref.watch(allProxiesOverviewProvider).error;
    final profileId = ref.watch(activeProfileProvider).valueOrNull?.id;
    final rules = effectiveRules(ref.watch(nodeBlacklistControllerProvider), profileId);
    final searchableGroups = [
      for (final group in groups)
        OutboundGroup(
          tag: group.tag,
          type: group.type,
          selected: group.selected,
          selectable: group.selectable,
          isExpand: group.isExpand,
          items: group.items.where((node) => !isNodeBlacklisted(node, rules)).toList(),
        ),
    ];
    final results = searchProxyGroups(searchableGroups, searchQuery.value);
    final displayedGroup = proxies.valueOrNull;

    int crossAxisCountForWidth(double width) =>
        PlatformUtils.isMobile && width < 600 ? 1 : max(1, (width / 420).floor());

    // ignore: no_leading_underscores_for_local_identifiers
    void _scrollToNode(String nodeTag) {
      final group = ref.read(proxiesOverviewNotifierProvider).valueOrNull;
      if (group == null || !scrollController.hasClients) return;
      final index = group.items.indexWhere((item) => item.tag == nodeTag);
      if (index < 0) return;
      final width = MediaQuery.sizeOf(context).width;
      final row = index ~/ crossAxisCountForWidth(width);
      scrollController.animateTo(row * 72.0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    }

    void onSearchResultSelected(ProxySearchResult result) {
      if (!searchableGroups.any((group) => group.tag == result.groupTag)) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.proxies.empty);
        return;
      }
      ref.read(activeProxyGroupNotifierProvider.notifier).select(result.groupTag);
      searchController.clear();
      searchQuery.value = '';
      pendingSearchTarget.value = result;
    }

    useEffect(() => searchController.dispose, []);

    useEffect(() {
      final target = pendingSearchTarget.value;
      if (target == null) return null;
      final group = displayedGroup;
      if (group == null || group.tag != target.groupTag) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToNode(target.nodeTag);
        _highlightedNode.value = target.nodeTag;
      });
      pendingSearchTarget.value = null;
      return null;
    }, [displayedGroup?.tag, pendingSearchTarget.value]);

    useEffect(() {
      if (didAutoLocate.value || displayedGroup == null || displayedGroup.selected.isEmpty) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToNode(displayedGroup.selected);
        didAutoLocate.value = true;
      });
      return null;
    }, [displayedGroup]);

    useEffect(() {
      final nodeTag = _highlightedNode.value;
      if (nodeTag == null) return null;
      final timer = Timer(const Duration(milliseconds: 1400), () {
        _highlightedNode.value = null;
      });
      return timer.cancel;
    }, [_highlightedNode.value]);

    // final selectActiveProxyMutation = useMutation(
    //   initialOnFailure: (error) => CustomToast.error(t.presentShortError(error)).show(context),
    // );

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.proxies.title),
        actions: [
          IconButton(
            tooltip: gridLayout.value ? 'List view' : 'Grid view',
            onPressed: () => gridLayout.value = !gridLayout.value,
            icon: Icon(gridLayout.value ? Icons.view_list_rounded : Icons.grid_view_rounded),
          ),
          IconButton(
            tooltip: t.pages.proxies.nodeBlacklist.title,
            onPressed: () => context.goNamed('nodeBlacklist'),
            icon: const Icon(Icons.block_rounded),
          ),
          PopupMenuButton<ProxiesSort>(
            initialValue: sortBy,
            onSelected: ref.read(proxiesSortNotifierProvider.notifier).update,
            icon: const Icon(FluentIcons.arrow_sort_24_regular),
            tooltip: t.pages.proxies.sort,
            itemBuilder: (context) {
              return [...ProxiesSort.values.map((e) => PopupMenuItem(value: e, child: Text(e.present(t))))];
            },
          ),
          // "Signal style" (off by default) shows pings as the signal instead of numbers
          PopupMenuButton<bool>(
            onSelected: (_) => ref.read(proxyPingStyleNotifierProvider.notifier).toggle(),
            icon: Icon(AdaptiveIcon(context).more),
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            itemBuilder: (context) => [
              // a null value would close the menu as cancelled
              PopupMenuItem(
                value: true,
                child: Row(
                  children: [
                    Checkbox(
                      value: ref.read(proxyPingStyleNotifierProvider) == ProxyPingStyle.signal,
                      // a tap on the box itself does what a tap on the item does
                      onChanged: (_) => Navigator.pop(context, true),
                    ),
                    const Gap(8),
                    Text(t.pages.proxies.signalStyle),
                  ],
                ),
              ),
            ],
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // the speed of the proxies listed: what it tests and the data it takes show first, and
          // it starts from there
          if (proxies.valueOrNull case final group?)
            FloatingActionButton.small(
              heroTag: 'upload-test',
              onPressed: () async {
                final count = group.items.where((e) => !e.isGroup).length;
                if (await ref.read(dialogNotifierProvider.notifier).showSpeedTest(count: count)) {
                  await ref.read(proxiesOverviewNotifierProvider.notifier).speedTestAll();
                }
              },
              tooltip: t.pages.proxies.speedTest.title,
              child: const Icon(Icons.speed_rounded, size: 26),
            ),
          const Gap(12),
          FloatingActionButton(
            heroTag: 'url-test',
            onPressed: () async =>
                await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(displayedGroup?.tag ?? "select"),
            tooltip: t.pages.proxies.testDelay,
            child: const Icon(FluentIcons.flash_24_filled),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: searchController,
              onChanged: (value) => searchQuery.value = value,
              decoration: InputDecoration(
                hintText: t.common.filter,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          if (allGroupsError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                t.presentShortError(allGroupsError),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: proxies.when(
                    data: (group) => group != null
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              final crossAxisCount = crossAxisCountForWidth(width);
                              final listed = group.items
                                  .where((e) => e.tag != lowestGroupTag && e.tag != balanceGroupTag)
                                  .length;
                              Widget tileBuilder(int index) {
                                final proxy = group.items[index];
                                final blacklisted = isNodeBlacklisted(proxy, rules);
                                final disabledReason = blacklisted
                                    ? t.pages.proxies.nodeBlacklist.nodeDisabled(name: proxy.tagDisplay)
                                    : null;
                                final tile = ProxyTile(
                                  proxy,
                                  // a row keeps its own proxy when the list re-sorts, so a pop plays only on arrival
                                  key: ValueKey(proxy.tag),
                                  selected: group.selected == proxy.tag,
                                  highlight: _highlightedNode.value == proxy.tag,
                                  disabled: blacklisted,
                                  blacklistReason: disabledReason,
                                  // a blacklisted node is kept out of the core, so no ping or speed test reaches it
                                  testable: !blacklisted,
                                  showPing: !blacklisted,
                                  onTap: () async {
                                    if (blacklisted) {
                                      ref
                                          .read(inAppNotificationControllerProvider)
                                          .showInfoToast(
                                            t.pages.proxies.nodeBlacklist.nodeDisabled(name: proxy.tagDisplay),
                                          );
                                      return;
                                    }
                                    await ref
                                        .read(proxiesOverviewNotifierProvider.notifier)
                                        .changeProxy(group.tag, proxy.tag);
                                  },
                                );
                                return blacklisted ? Tooltip(message: disabledReason, child: tile) : tile;
                              }

                              return CustomScrollView(
                                controller: scrollController,
                                slivers: [
                                  if (gridLayout.value)
                                    SliverGrid.builder(
                                      itemCount: group.items.length,
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        mainAxisExtent: 72,
                                      ),
                                      itemBuilder: (context, index) => tileBuilder(index),
                                    )
                                  else
                                    SliverList.builder(
                                      itemCount: group.items.length,
                                      itemBuilder: (context, index) => tileBuilder(index),
                                    ),
                                  // a big profile: how many of its proxies run, and the button to run all or the fastest
                                  SliverToBoxAdapter(child: KeepTopFooter(listed: listed)),
                                  // room for the buttons over the list's end
                                  const SliverPadding(padding: EdgeInsets.only(bottom: 140)),
                                ],
                              );
                            },
                          )
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                ref.watch(serviceRunningProvider)
                                    ? t.pages.proxies.empty
                                    : t.pages.proxies.connectToSeeProxies,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                    error: (error, stackTrace) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t.pages.proxies.loadFailed, textAlign: TextAlign.center),
                            const Gap(12),
                            TextButton(
                              onPressed: () => ref.invalidate(proxiesOverviewNotifierProvider),
                              child: Text(t.connection.tapToRetry),
                            ),
                          ],
                        ),
                      ),
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                  ),
                ),
                if (searchQuery.value.isNotEmpty && results.isEmpty)
                  Center(child: Text(t.pages.proxies.empty))
                else if (results.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 86),
                    child: ProxySearchOverlay(results: results, onSelected: onSearchResultSelected),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
