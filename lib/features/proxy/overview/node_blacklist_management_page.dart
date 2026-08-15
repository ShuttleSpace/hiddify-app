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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final rule = await showDialog<NodeBlacklistRule>(
            context: context,
            builder: (context) => const _AddNodeBlacklistRuleDialog(),
          );
          if (rule == null) return;
          if (profileId == null) {
            await ref.read(nodeBlacklistControllerProvider.notifier).upsertGlobalRule(rule);
          } else {
            await ref.read(nodeBlacklistControllerProvider.notifier).upsertProviderRule(profileId!, rule);
          }
        },
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _AddNodeBlacklistRuleDialog extends StatefulWidget {
  const _AddNodeBlacklistRuleDialog();

  @override
  State<_AddNodeBlacklistRuleDialog> createState() => _AddNodeBlacklistRuleDialogState();
}

class _AddNodeBlacklistRuleDialogState extends State<_AddNodeBlacklistRuleDialog> {
  final _nameController = TextEditingController();
  final _valueController = TextEditingController();
  NodeBlacklistField _field = NodeBlacklistField.countryCode;
  NodeBlacklistOperator _operator = NodeBlacklistOperator.equals;
  NodeBlacklistMatchMode _matchMode = NodeBlacklistMatchMode.any;

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add blacklist rule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Rule name'),
          ),
          DropdownButtonFormField<NodeBlacklistMatchMode>(
            initialValue: _matchMode,
            decoration: const InputDecoration(labelText: 'Match mode'),
            items: NodeBlacklistMatchMode.values
                .map((mode) => DropdownMenuItem(value: mode, child: Text(mode.name)))
                .toList(),
            onChanged: (value) => setState(() => _matchMode = value ?? NodeBlacklistMatchMode.any),
          ),
          DropdownButtonFormField<NodeBlacklistField>(
            initialValue: _field,
            decoration: const InputDecoration(labelText: 'Field'),
            items: NodeBlacklistField.values
                .map((field) => DropdownMenuItem(value: field, child: Text(field.name)))
                .toList(),
            onChanged: (value) => setState(() => _field = value ?? NodeBlacklistField.countryCode),
          ),
          DropdownButtonFormField<NodeBlacklistOperator>(
            initialValue: _operator,
            decoration: const InputDecoration(labelText: 'Operator'),
            items: NodeBlacklistOperator.values
                .map((operator) => DropdownMenuItem(value: operator, child: Text(operator.name)))
                .toList(),
            onChanged: (value) => setState(() => _operator = value ?? NodeBlacklistOperator.equals),
          ),
          TextField(
            controller: _valueController,
            decoration: const InputDecoration(labelText: 'Value'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final rule = NodeBlacklistRule(
              enabled: true,
              name: _nameController.text.trim().isEmpty ? 'Custom rule' : _nameController.text.trim(),
              matchMode: _matchMode,
              conditions: [
                NodeBlacklistCondition(
                  field: _field,
                  operator: _operator,
                  value: _valueController.text.trim(),
                ),
              ],
            );
            Navigator.of(context).pop(rule);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
