import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/proxy/data/node_blacklist_io.dart';
import 'package:hiddify/features/proxy/model/node_blacklist.dart';
import 'package:hiddify/features/proxy/notifier/node_blacklist_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NodeBlacklistManagementPage extends ConsumerWidget {
  const NodeBlacklistManagementPage({super.key, this.profileId});

  final String? profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(nodeBlacklistControllerProvider);
    final provider = profileId == null ? null : document.providers[profileId];
    final rules = profileId == null ? document.globalRules : provider?.rules ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Node Blacklist'),
        actions: [
          IconButton(
            tooltip: 'Copy JSON',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => Clipboard.setData(ClipboardData(text: exportToJson(document))),
          ),
          IconButton(
            tooltip: 'Paste JSON',
            icon: const Icon(Icons.content_paste_rounded),
            onPressed: () async {
              final text = await Clipboard.getData(Clipboard.kTextPlain);
              if (text?.text == null) return;
              ref
                  .read(nodeBlacklistControllerProvider.notifier)
                  .importDocument(importFromJson(text!.text!));
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          if (profileId != null)
            DropdownButton<NodeBlacklistPolicy>(
              value: provider?.policy ?? NodeBlacklistPolicy.useGlobal,
              items: NodeBlacklistPolicy.values
                  .map((policy) => DropdownMenuItem(value: policy, child: Text(policy.name)))
                  .toList(),
              onChanged: (policy) {
                if (policy != null) {
                  ref.read(nodeBlacklistControllerProvider.notifier).setProviderPolicy(profileId!, policy);
                }
              },
            ),
          for (var i = 0; i < rules.length; i++)
            ListTile(
              title: Text(rules[i].name),
              subtitle: Text(rules[i].matchMode.name),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  if (profileId == null) {
                    ref.read(nodeBlacklistControllerProvider.notifier).deleteGlobalRule(i);
                  } else {
                    ref.read(nodeBlacklistControllerProvider.notifier).deleteProviderRule(profileId!, i);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
