import 'dart:async';
import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/domain/proxy_search.dart';
import 'package:hiddify/features/proxy/keep_top/keep_top_widgets.dart';
import 'package:hiddify/features/proxy/model/proxy_entity.dart';
import 'package:hiddify/features/proxy/model/proxy_search_result.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_search_overlay.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxiesOverviewPage extends HookConsumerWidget with PresLogger {
  const ProxiesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);

    final searchQuery = useState('');
    final searchController = useMemoized(TextEditingController.new);
    // ignore: no_leading_underscores_for_local_identifiers
    final _highlightedNode = useState<String?>(null);
    final pendingSearchTarget = useState<ProxySearchResult?>(null);
    final didAutoLocate = useState(false);
    final scrollController = useScrollController();

    final displayedGroup = proxies.valueOrNull;
    // The page shows one group (the core's main group); search runs over its rows.
    final results = displayedGroup == null
        ? const <ProxySearchResult>[]
        : searchProxyGroups([displayedGroup], searchQuery.value);

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
      searchController.clear();
      searchQuery.value = '';
      pendingSearchTarget.value = result;
    }

    useEffect(() => searchController.dispose, []);

    // Jump to a node picked from the search overlay once its group is shown.
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

    // On first load, bring the selected node into view.
    useEffect(() {
      if (didAutoLocate.value || displayedGroup == null || displayedGroup.selected.isEmpty) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToNode(displayedGroup.selected);
        didAutoLocate.value = true;
      });
      return null;
    }, [displayedGroup]);

    // The highlight fades a moment after a jump.
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
            onPressed: () async => await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest("select"),
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
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: proxies.when(
                    data: (group) => group != null
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              // columns wide enough for a proxy's name: two on a usual window, more only when wider
                              final crossAxisCount = PlatformUtils.isMobile && width < 600
                                  ? 1
                                  : max(1, (width / 420).floor());
                              final listed = group.items
                                  .where((e) => e.tag != lowestGroupTag && e.tag != balanceGroupTag)
                                  .length;
                              return CustomScrollView(
                                controller: scrollController,
                                slivers: [
                                  SliverGrid.builder(
                                    itemCount: group.items.length,
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      mainAxisExtent: 72,
                                    ),
                                    itemBuilder: (context, index) {
                                      final proxy = group.items[index];
                                      return ProxyTile(
                                        proxy,
                                        // a row keeps its own proxy when the list re-sorts, so a pop plays only on arrival
                                        key: ValueKey(proxy.tag),
                                        selected: group.selected == proxy.tag,
                                        highlight: _highlightedNode.value == proxy.tag,
                                        onTap: () async {
                                          await ref
                                              .read(proxiesOverviewNotifierProvider.notifier)
                                              .changeProxy(group.tag, proxy.tag);
                                        },
                                      );
                                    },
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
