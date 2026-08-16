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
        : entries.where((entry) => _fuzzyMatch(searchQuery.value, entry.title)).toList();

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
                isDense: true,
              ),
            ),
          ),
          if (searchResults != null)
            if (searchResults.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(t.pages.proxies.empty)),
              )
            else
              for (final entry in searchResults)
                ListTile(
                  leading: Icon(entry.icon),
                  title: Text(entry.title),
                  subtitle: entry.subtitle == null ? null : Text(entry.subtitle!),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.go(entry.namedLocation),
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
      _SettingsSearchEntry(t.pages.settings.general.title, Icons.layers_rounded, context.namedLocation('general')),
      _SettingsSearchEntry(
        t.pages.settings.appearance.title,
        Icons.palette_rounded,
        context.namedLocation('appearance'),
      ),
      _SettingsSearchEntry(t.pages.settings.traffic.title, Icons.speed_rounded, context.namedLocation('trafficStats')),
      _SettingsSearchEntry(
        t.pages.settings.networkIdentity.title,
        Icons.public_rounded,
        context.namedLocation('networkIdentity'),
      ),
      _SettingsSearchEntry(t.pages.settings.backup.title, Icons.backup_rounded, context.namedLocation('backup')),
      _SettingsSearchEntry(
        t.pages.settings.shortcuts.title,
        Icons.keyboard_command_key_rounded,
        context.namedLocation('shortcuts'),
      ),
      if (ref.watch(hasAnyProfileProvider).value ?? false)
        _SettingsSearchEntry(
          t.pages.settings.chain.title,
          Icons.webhook_rounded,
          context.namedLocation('chainOptions'),
          subtitle: t.pages.settings.chain.subtitle,
        ),
      _SettingsSearchEntry(
        t.pages.settings.routing.title,
        Icons.route_rounded,
        context.namedLocation('routingOptions'),
      ),
      _SettingsSearchEntry(t.pages.settings.dns.title, Icons.dns_rounded, context.namedLocation('dnsOptions')),
      _SettingsSearchEntry(
        t.pages.settings.inbound.title,
        Icons.input_rounded,
        context.namedLocation('inboundOptions'),
      ),
      _SettingsSearchEntry(
        t.pages.settings.tlsTricks.title,
        Icons.content_cut_rounded,
        context.namedLocation('tlsTricks'),
      ),
      if (Breakpoint(context).isMobile()) ...[
        _SettingsSearchEntry(t.pages.logs.title, Icons.description_rounded, context.namedLocation('logs')),
        _SettingsSearchEntry(t.pages.about.title, Icons.info_rounded, context.namedLocation('about')),
      ],
    ];
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
  const _SettingsSearchEntry(this.title, this.icon, this.namedLocation, {this.subtitle});

  final String title;
  final IconData icon;
  final String namedLocation;
  final String? subtitle;
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
