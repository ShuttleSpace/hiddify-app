import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NetworkIdentityPage extends HookConsumerWidget {
  const NetworkIdentityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final info = ref.watch(ipInfoNotifierProvider);
    final rules = ref.watch(rulesNotifierProvider);
    final geoReferences =
        rules
            .expand((rule) => rule.ruleSets)
            .where((value) => value.startsWith('geoip-') || value.startsWith('geosite-'))
            .toSet()
            .toList()
          ..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.settings.networkIdentity.title),
        actions: [
          IconButton(
            tooltip: t.pages.settings.networkIdentity.refresh,
            onPressed: () => ref.read(ipInfoNotifierProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: switch (info) {
                AsyncData(value: final value) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IPCountryFlag(countryCode: value.countryCode, size: 32),
                        const Gap(8),
                        Expanded(child: Text(value.ip, style: Theme.of(context).textTheme.titleMedium)),
                      ],
                    ),
                    const Gap(12),
                    _InfoRow(label: t.pages.settings.networkIdentity.country, value: value.countryCode.toUpperCase()),
                    if (value.region?.isNotEmpty ?? false)
                      _InfoRow(label: t.pages.settings.networkIdentity.region, value: value.region!),
                    if (value.city?.isNotEmpty ?? false)
                      _InfoRow(label: t.pages.settings.networkIdentity.city, value: value.city!),
                    if (value.asn?.isNotEmpty ?? false)
                      _InfoRow(label: t.pages.settings.networkIdentity.asn, value: value.asn!),
                    if (value.org?.isNotEmpty ?? false)
                      _InfoRow(label: t.pages.settings.networkIdentity.organization, value: value.org!),
                  ],
                ),
                AsyncLoading() => const Center(child: CircularProgressIndicator()),
                _ => Center(child: Text(t.pages.settings.networkIdentity.notAvailable)),
              },
            ),
          ),
          const Gap(16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.pages.settings.networkIdentity.resources, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Gap(8),
                  Text(t.pages.settings.networkIdentity.resourcesMsg),
                  const Gap(8),
                  if (geoReferences.isEmpty)
                    Text(t.pages.settings.networkIdentity.noReferences)
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [for (final reference in geoReferences) Chip(label: Text(reference))],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
