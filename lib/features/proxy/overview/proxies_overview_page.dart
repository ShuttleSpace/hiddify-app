import 'dart:async';
import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/features/proxy/domain/proxy_search.dart';
import 'package:hiddify/features/proxy/model/proxy_search_result.dart';
import 'package:hiddify/features/proxy/notifier/active_proxy_group_notifier.dart';
import 'package:hiddify/features/proxy/overview/all_proxies_overview_provider.dart';
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
    // ignore: no_leading_underscores_for_local_identifiers
    final _highlightedNode = useState<String?>(null);
    final didAutoLocate = useState(false);
    final scrollController = useScrollController();

    final groups = ref.watch(allProxiesOverviewProvider).valueOrNull ?? const [];
    final results = searchProxyGroups(groups, searchQuery.value);
    final displayedGroup = proxies.valueOrNull;

    int crossAxisCountForWidth(double width) =>
        PlatformUtils.isMobile && width < 600 ? 1 : max(1, (width / 268).floor());

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
      ref.read(activeProxyGroupNotifierProvider.notifier).select(result.groupTag);
      searchQuery.value = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToNode(result.nodeTag);
        _highlightedNode.value = result.nodeTag;
      });
    }

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
            tooltip: 'Node blacklist',
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
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async => await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest("select"),
        tooltip: t.pages.proxies.testDelay,
        child: const Icon(FluentIcons.flash_24_filled),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (value) => searchQuery.value = value,
              decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search), isDense: true),
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
                              return GridView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.only(bottom: 86),
                                itemCount: group.items.length,
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisExtent: 72,
                                ),
                                itemBuilder: (context, index) {
                                  final proxy = group.items[index];
                                  return ProxyTile(
                                    proxy,
                                    selected: group.selected == proxy.tag,
                                    highlight: _highlightedNode.value == proxy.tag,
                                    onTap: () async {
                                      await ref
                                          .read(proxiesOverviewNotifierProvider.notifier)
                                          .changeProxy(group.tag, proxy.tag);
                                      // if (selectActiveProxyMutation.state.isInProgress) return;
                                      // selectActiveProxyMutation.setFuture(
                                      // );
                                    },
                                  );
                                },
                              );
                            },
                          )
                        : Center(child: Text(t.pages.proxies.empty)),
                    error: (error, stackTrace) => Center(child: Text(t.presentShortError(error))),
                    loading: () => const Center(child: CircularProgressIndicator()),
                  ),
                ),
                if (results.isNotEmpty)
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
