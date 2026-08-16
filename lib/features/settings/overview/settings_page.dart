import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum ConfigOptionSection {
  warp,
  fragment;

  static final _warpKey = GlobalKey(debugLabel: "warp-section-key");
  static final _fragmentKey = GlobalKey(debugLabel: "fragment-section-key");

  GlobalKey get key => switch (this) {
    ConfigOptionSection.warp => _warpKey,
    ConfigOptionSection.fragment => _fragmentKey,
  };
}

class SettingsPage extends HookConsumerWidget {
  SettingsPage({super.key, String? section})
    : section = section != null ? ConfigOptionSection.values.byName(section) : null;

  final ConfigOptionSection? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final searchQuery = useState('');
    final searchController = useTextEditingController();
    final entries = _buildSearchEntries(context, ref, t);
    final searchResults = searchQuery.value.trim().isEmpty
        ? null
        : _groupSearchEntries(entries, entries.where((entry) => _matchesSearchEntry(searchQuery.value, entry)).toSet());

    useEffect(() => searchController.dispose, []);
    // final scrollController = useScrollController();

    // useMemoized(
    //   () {
    //     if (section != null) {
    //       WidgetsBinding.instance.addPostFrameCallback(
    //         (_) {
    //           final box = section!.key.currentContext?.findRenderObject() as RenderBox?;

    //           final offset = box?.localToGlobal(Offset.zero);
    //           if (offset == null) return;
    //           final height = scrollController.offset + offset.dy - MediaQueryData.fromView(View.of(context)).padding.top - kToolbarHeight;
    //           scrollController.animateTo(
    //             height,
    //             duration: const Duration(milliseconds: 500),
    //             curve: Curves.decelerate,
    //           );
    //         },
    //       );
    //     }
    //   },
    // );

    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.title)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: searchController,
              onChanged: (value) => searchQuery.value = value,
              decoration: InputDecoration(
                hintText: t.common.filter,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchQuery.value.isEmpty
                    ? null
                    : IconButton(
                        tooltip: t.common.clear,
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          searchController.clear();
                          searchQuery.value = '';
                        },
                      ),
                isDense: true,
              ),
            ),
          ),
          if (searchResults != null)
            if (searchResults.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(t.common.empty)),
              )
            else
              for (final group in searchResults)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Icon(group.icon, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(group.title, style: Theme.of(context).textTheme.titleMedium)),
                          ],
                        ),
                      ),
                      if (group.children.isEmpty)
                        ListTile(
                          title: _highlightedText(context, searchQuery.value, group.title),
                          onTap: () => context.go(group.namedLocation),
                        )
                      else
                        for (final child in group.children)
                          ListTile(
                            dense: true,
                            leading: Icon(child.icon, size: 20),
                            title: _highlightedText(context, searchQuery.value, child.title),
                            subtitle: child.subtitle == null ? null : Text(child.subtitle!),
                            onTap: () => context.go(child.namedLocation),
                          ),
                    ],
                  ),
                )
          else ...[
            // TipCard(message: t.settings.experimentalMsg),
            SettingsSection(
              title: t.pages.settings.general.title,
              icon: Icons.layers_rounded,
              namedLocation: context.namedLocation('general'),
            ),
            SettingsSection(
              title: t.pages.settings.appearance.title,
              icon: Icons.palette_rounded,
              namedLocation: context.namedLocation('appearance'),
            ),
            SettingsSection(
              title: t.pages.settings.traffic.title,
              icon: Icons.speed_rounded,
              namedLocation: context.namedLocation('trafficStats'),
            ),
            SettingsSection(
              title: t.pages.settings.networkIdentity.title,
              icon: Icons.public_rounded,
              namedLocation: context.namedLocation('networkIdentity'),
            ),
            SettingsSection(
              title: t.pages.settings.backup.title,
              icon: Icons.backup_rounded,
              namedLocation: context.namedLocation('backup'),
            ),
            SettingsSection(
              title: t.pages.settings.shortcuts.title,
              icon: Icons.keyboard_command_key_rounded,
              namedLocation: context.namedLocation('shortcuts'),
            ),
            if (ref.watch(hasAnyProfileProvider).value ?? false)
              SettingsSection(
                title: t.pages.settings.chain.title,
                icon: Icons.webhook_rounded,
                subtitle: Text(t.pages.settings.chain.subtitle),
                namedLocation: context.namedLocation('chainOptions'),
              ),
            SettingsSection(
              title: t.pages.settings.routing.title,
              icon: Icons.route_rounded,
              namedLocation: context.namedLocation('routingOptions'),
            ),
            SettingsSection(
              title: t.pages.settings.dns.title,
              icon: Icons.dns_rounded,
              namedLocation: context.namedLocation('dnsOptions'),
            ),
            SettingsSection(
              title: t.pages.settings.inbound.title,
              icon: Icons.input_rounded,
              namedLocation: context.namedLocation('inboundOptions'),
            ),
            SettingsSection(
              title: t.pages.settings.tlsTricks.title,
              icon: Icons.content_cut_rounded,
              namedLocation: context.namedLocation('tlsTricks'),
            ),
            if (PlatformUtils.isIOS)
              Material(
                child: ListTile(
                  title: Text(t.pages.settings.resetTunnel),
                  leading: const Icon(Icons.autorenew_rounded),
                  onTap: () async {
                    await ref.read(resetTunnelNotifierProvider.notifier).run();
                  },
                ),
              ),
            if (Breakpoint(context).isMobile()) ...[
              SettingsSection(
                title: t.pages.logs.title,
                icon: Icons.description_rounded,
                namedLocation: context.namedLocation('logs'),
              ),
              SettingsSection(
                title: t.pages.about.title,
                icon: Icons.info_rounded,
                namedLocation: context.namedLocation('about'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<_SettingsSearchEntry> _buildSearchEntries(BuildContext context, WidgetRef ref, Translations t) {
    return [
      _SettingsSearchEntry(
        t.pages.settings.general.openMainWindowOnStartup,
        Icons.open_in_new_rounded,
        context.namedLocation('general'),
        subtitle: t.pages.settings.general.title,
        parentTitle: t.pages.settings.general.title,
        keywords: const ['打开', '启动', '主界面', '窗口', 'open', 'start'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.appearance.textSize,
        Icons.text_fields_rounded,
        context.namedLocation('appearance'),
        subtitle: t.pages.settings.appearance.title,
        parentTitle: t.pages.settings.appearance.title,
        keywords: const ['文本', '大小', '缩放', 'text', 'size'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.appearance.themeColor,
        Icons.color_lens_rounded,
        context.namedLocation('appearance'),
        subtitle: t.pages.settings.appearance.title,
        parentTitle: t.pages.settings.appearance.title,
        keywords: const ['主题', '颜色', '外观', 'theme', 'color'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.inbound.serviceMode,
        Icons.input_rounded,
        context.namedLocation('inboundOptions'),
        subtitle: t.pages.settings.inbound.title,
        parentTitle: t.pages.settings.inbound.title,
        keywords: const ['系统代理', 'TUN', '代理模式', 'service', 'mode'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.inbound.mixedPort,
        Icons.numbers_rounded,
        context.namedLocation('inboundOptions'),
        subtitle: t.pages.settings.inbound.title,
        parentTitle: t.pages.settings.inbound.title,
        keywords: const ['端口', '混合', 'port'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.dns.remoteDns,
        Icons.dns_rounded,
        context.namedLocation('dnsOptions'),
        subtitle: t.pages.settings.dns.title,
        parentTitle: t.pages.settings.dns.title,
        keywords: const ['DNS', '远程', '域名'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.dns.enableFakeDns,
        Icons.dns_rounded,
        context.namedLocation('dnsOptions'),
        subtitle: t.pages.settings.dns.title,
        parentTitle: t.pages.settings.dns.title,
        keywords: const ['DNS', 'Fake', '域名'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.routing.generalOptions.region,
        Icons.route_rounded,
        context.namedLocation('routingOptions'),
        subtitle: t.pages.settings.routing.title,
        parentTitle: t.pages.settings.routing.title,
        keywords: const ['地区', '区域', '路由', 'region'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.routing.generalOptions.resolveDestination,
        Icons.route_rounded,
        context.namedLocation('routingOptions'),
        subtitle: t.pages.settings.routing.title,
        parentTitle: t.pages.settings.routing.title,
        keywords: const ['解析', '域名', '目的地', 'resolve'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.general.title,
        Icons.layers_rounded,
        context.namedLocation('general'),
        keywords: const ['常规', '通用', 'general', '语言', '内存', '调试', '日志级别'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.appearance.title,
        Icons.palette_rounded,
        context.namedLocation('appearance'),
        keywords: const ['外观', '主题', '颜色', '文本', '缩放'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.traffic.title,
        Icons.speed_rounded,
        context.namedLocation('trafficStats'),
        keywords: const ['流量', '网速', '统计', '历史', 'traffic', 'speed'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.networkIdentity.title,
        Icons.public_rounded,
        context.namedLocation('networkIdentity'),
        keywords: const ['网络', '身份', '国家', '地区', '城市', 'ASN', 'GeoIP'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.backup.title,
        Icons.backup_rounded,
        context.namedLocation('backup'),
        keywords: const ['备份', '恢复', 'WebDAV', '本地', '导入', '导出', 'backup'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.shortcuts.title,
        Icons.keyboard_command_key_rounded,
        context.namedLocation('shortcuts'),
        keywords: const ['快捷键', '热键', '打开设置', 'shortcut'],
      ),
      if (ref.watch(hasAnyProfileProvider).value ?? false)
        _SettingsSearchEntry(
          t.pages.settings.chain.title,
          Icons.webhook_rounded,
          context.namedLocation('chainOptions'),
          subtitle: t.pages.settings.chain.subtitle,
          keywords: const ['链', 'WARP', 'Psiphon', '中转'],
        ),
      _SettingsSearchEntry(
        t.pages.settings.routing.title,
        Icons.route_rounded,
        context.namedLocation('routingOptions'),
        keywords: const ['路由', '规则', '直连', '代理', '局域网', 'GeoIP', 'GeoSite'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.dns.title,
        Icons.dns_rounded,
        context.namedLocation('dnsOptions'),
        keywords: const ['DNS', '远程', '直连', 'Fake', '域名'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.inbound.title,
        Icons.input_rounded,
        context.namedLocation('inboundOptions'),
        keywords: const ['入站', '端口', 'TUN', '系统代理', '局域网', 'inbound'],
      ),
      _SettingsSearchEntry(
        t.pages.settings.tlsTricks.title,
        Icons.content_cut_rounded,
        context.namedLocation('tlsTricks'),
        keywords: const ['TLS', '分片', 'Padding', 'SNI', '伪装'],
      ),
      if (Breakpoint(context).isMobile()) ...[
        _SettingsSearchEntry(
          t.pages.logs.title,
          Icons.description_rounded,
          context.namedLocation('logs'),
          keywords: const ['日志', 'log'],
        ),
        _SettingsSearchEntry(
          t.pages.about.title,
          Icons.info_rounded,
          context.namedLocation('about'),
          keywords: const ['关于', '版本', 'about'],
        ),
      ],
    ];
  }

  List<_SettingsSearchGroup> _groupSearchEntries(
    Iterable<_SettingsSearchEntry> allEntries,
    Set<_SettingsSearchEntry> matchedEntries,
  ) {
    final entryList = allEntries.toList();
    final parentEntries = <String, _SettingsSearchEntry>{};
    final childEntriesByLocation = <String, List<_SettingsSearchEntry>>{};

    for (final entry in entryList) {
      if (entry.parentTitle == null) {
        parentEntries[entry.namedLocation] = entry;
      } else {
        childEntriesByLocation.putIfAbsent(entry.namedLocation, () => []).add(entry);
      }
    }

    final result = <_SettingsSearchGroup>[];
    final locations = <String>{...parentEntries.keys, ...childEntriesByLocation.keys};
    for (final location in locations) {
      final parent = parentEntries[location];
      final children = childEntriesByLocation[location] ?? const <_SettingsSearchEntry>[];
      if (parent == null && children.isEmpty) continue;

      final parentMatched = parent != null && matchedEntries.contains(parent);
      final matchedChildren = parentMatched ? children : children.where(matchedEntries.contains).toList();
      if (!parentMatched && matchedChildren.isEmpty) continue;

      result.add(
        _SettingsSearchGroup(
          title: parent?.title ?? matchedChildren.first.title,
          icon: parent?.icon ?? matchedChildren.first.icon,
          namedLocation: location,
          children: matchedChildren,
        ),
      );
    }
    return result;
  }

  Widget _highlightedText(BuildContext context, String query, String text) {
    final highlightStyle = TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700);
    return Text.rich(TextSpan(children: _highlightSpans(query, text, highlightStyle)));
  }

  List<TextSpan> _highlightSpans(String query, String text, TextStyle highlightStyle) {
    final tokens = query.trim().split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toSet().toList();
    if (tokens.isEmpty) return [TextSpan(text: text)];

    final matches = <({int start, int end})>[];
    for (final token in tokens) {
      final pattern = RegExp(RegExp.escape(token), caseSensitive: false);
      for (final match in pattern.allMatches(text)) {
        matches.add((start: match.start, end: match.end));
      }
    }
    if (matches.isEmpty) return [TextSpan(text: text)];

    matches.sort((a, b) => a.start.compareTo(b.start));
    final merged = <({int start, int end})>[];
    for (final match in matches) {
      if (merged.isEmpty || match.start > merged.last.end) {
        merged.add(match);
      } else {
        final previous = merged.removeLast();
        merged.add((start: previous.start, end: match.end > previous.end ? match.end : previous.end));
      }
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in merged) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(TextSpan(text: text.substring(match.start, match.end), style: highlightStyle));
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }

  bool _matchesSearchEntry(String query, _SettingsSearchEntry entry) {
    if (_fuzzyMatch(query, entry.title)) return true;
    if (entry.subtitle != null && _fuzzyMatch(query, entry.subtitle!)) return true;
    return entry.keywords.any((keyword) => _fuzzyMatch(query, keyword));
  }

  bool _fuzzyMatch(String query, String text) {
    final needle = query.toLowerCase().replaceAll(' ', '');
    final haystack = text.toLowerCase();
    if (haystack.contains(needle)) return true;
    var index = 0;
    for (final char in haystack.split('')) {
      if (index < needle.length && char == needle[index]) index++;
    }
    return index == needle.length;
  }
}

class _SettingsSearchEntry {
  const _SettingsSearchEntry(
    this.title,
    this.icon,
    this.namedLocation, {
    this.subtitle,
    this.parentTitle,
    this.keywords = const [],
  });

  final String title;
  final IconData icon;
  final String namedLocation;
  final String? subtitle;
  final String? parentTitle;
  final List<String> keywords;
}

class _SettingsSearchGroup {
  _SettingsSearchGroup({
    required this.title,
    required this.icon,
    required this.namedLocation,
    this.children = const [],
  });

  String title;
  IconData icon;
  final String namedLocation;
  final List<_SettingsSearchEntry> children;
}

class SettingsSection extends HookConsumerWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    required this.namedLocation,
  });

  final String title;
  final Widget? subtitle;
  final IconData icon;
  final String namedLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.go(namedLocation),
    );
  }
}
