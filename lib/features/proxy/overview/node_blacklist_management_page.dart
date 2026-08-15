import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/proxy/data/node_blacklist_io.dart';
import 'package:hiddify/features/proxy/model/node_blacklist.dart';
import 'package:hiddify/features/proxy/notifier/node_blacklist_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NodeBlacklistManagementPage extends ConsumerWidget {
  const NodeBlacklistManagementPage({super.key, this.profileId});

  final String? profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final document = ref.watch(nodeBlacklistControllerProvider);
    final provider = profileId == null ? null : document.providers[profileId];
    final rules = profileId == null ? document.globalRules : provider?.rules ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.proxies.nodeBlacklist.title),
        actions: [
          IconButton(
            tooltip: t.pages.proxies.nodeBlacklist.copyJson,
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => Clipboard.setData(ClipboardData(text: exportToJson(document))),
          ),
          IconButton(
            tooltip: t.pages.proxies.nodeBlacklist.pasteJson,
            icon: const Icon(Icons.content_paste_rounded),
            onPressed: () async {
              final text = await Clipboard.getData(Clipboard.kTextPlain);
              if (text?.text == null) return;
              ref.read(nodeBlacklistControllerProvider.notifier).importDocument(importFromJson(text!.text!));
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: rules[i].enabled
                        ? t.pages.proxies.nodeBlacklist.disableRule
                        : t.pages.proxies.nodeBlacklist.enableRule,
                    child: Switch(
                      value: rules[i].enabled,
                      onChanged: (enabled) {
                        if (profileId == null) {
                          ref.read(nodeBlacklistControllerProvider.notifier).setGlobalRuleEnabled(i, enabled);
                        } else {
                          ref
                              .read(nodeBlacklistControllerProvider.notifier)
                              .setProviderRuleEnabled(profileId!, i, enabled);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: t.pages.proxies.nodeBlacklist.edit,
                    onPressed: () async {
                      final updated = await showDialog<NodeBlacklistRule>(
                        context: context,
                        builder: (context) => _EditNodeBlacklistRuleDialog(t: t, rule: rules[i]),
                      );
                      if (updated == null) return;
                      if (profileId == null) {
                        await ref.read(nodeBlacklistControllerProvider.notifier).upsertGlobalRule(updated, index: i);
                      } else {
                        await ref
                            .read(nodeBlacklistControllerProvider.notifier)
                            .upsertProviderRule(profileId!, updated, index: i);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: t.pages.proxies.nodeBlacklist.delete,
                    onPressed: () {
                      if (profileId == null) {
                        ref.read(nodeBlacklistControllerProvider.notifier).deleteGlobalRule(i);
                      } else {
                        ref.read(nodeBlacklistControllerProvider.notifier).deleteProviderRule(profileId!, i);
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final rule = await showDialog<NodeBlacklistRule>(
            context: context,
            builder: (context) => _AddNodeBlacklistRuleDialog(t: t),
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
  const _AddNodeBlacklistRuleDialog({required this.t});

  final Translations t;

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
    final labels = widget.t.pages.proxies.nodeBlacklist;
    return AlertDialog(
      title: Text(labels.addRule),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: labels.ruleName),
          ),
          DropdownButtonFormField<NodeBlacklistMatchMode>(
            initialValue: _matchMode,
            decoration: InputDecoration(labelText: labels.matchMode),
            items: NodeBlacklistMatchMode.values
                .map((mode) => DropdownMenuItem(value: mode, child: Text(mode.name)))
                .toList(),
            onChanged: (value) => setState(() => _matchMode = value ?? NodeBlacklistMatchMode.any),
          ),
          DropdownButtonFormField<NodeBlacklistField>(
            initialValue: _field,
            decoration: InputDecoration(labelText: labels.field),
            items: NodeBlacklistField.values
                .map((field) => DropdownMenuItem(value: field, child: Text(field.name)))
                .toList(),
            onChanged: (value) => setState(() => _field = value ?? NodeBlacklistField.countryCode),
          ),
          DropdownButtonFormField<NodeBlacklistOperator>(
            initialValue: _operator,
            decoration: InputDecoration(labelText: labels.operator),
            items: NodeBlacklistOperator.values
                .map((operator) => DropdownMenuItem(value: operator, child: Text(operator.name)))
                .toList(),
            onChanged: (value) => setState(() => _operator = value ?? NodeBlacklistOperator.equals),
          ),
          TextField(
            controller: _valueController,
            decoration: InputDecoration(labelText: labels.value),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(labels.cancel)),
        FilledButton(
          onPressed: () {
            final rule = NodeBlacklistRule(
              enabled: true,
              name: _nameController.text.trim().isEmpty ? 'Custom rule' : _nameController.text.trim(),
              matchMode: _matchMode,
              conditions: [
                NodeBlacklistCondition(field: _field, operator: _operator, value: _valueController.text.trim()),
              ],
            );
            Navigator.of(context).pop(rule);
          },
          child: Text(labels.save),
        ),
      ],
    );
  }
}

class _EditNodeBlacklistRuleDialog extends StatefulWidget {
  const _EditNodeBlacklistRuleDialog({required this.t, required this.rule});

  final Translations t;
  final NodeBlacklistRule rule;

  @override
  State<_EditNodeBlacklistRuleDialog> createState() => _EditNodeBlacklistRuleDialogState();
}

class _EditNodeBlacklistRuleDialogState extends State<_EditNodeBlacklistRuleDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _valueController;
  late final TextEditingController _jsonController;
  late NodeBlacklistField _field;
  late NodeBlacklistOperator _operator;
  late NodeBlacklistMatchMode _matchMode;
  bool _formMode = true;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    final firstCondition = rule.conditions.isEmpty
        ? const NodeBlacklistCondition(
            field: NodeBlacklistField.countryCode,
            operator: NodeBlacklistOperator.equals,
            value: '',
          )
        : rule.conditions.first;
    _nameController = TextEditingController(text: rule.name);
    _valueController = TextEditingController(text: firstCondition.value);
    _jsonController = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(rule.toJson()));
    _field = firstCondition.field;
    _operator = firstCondition.operator;
    _matchMode = rule.matchMode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  NodeBlacklistRule _buildFormRule() {
    return NodeBlacklistRule(
      enabled: widget.rule.enabled,
      name: _nameController.text.trim().isEmpty ? 'Custom rule' : _nameController.text.trim(),
      matchMode: _matchMode,
      conditions: [NodeBlacklistCondition(field: _field, operator: _operator, value: _valueController.text.trim())],
    );
  }

  NodeBlacklistRule _buildEditorRule() {
    return NodeBlacklistRule.fromJson(jsonDecode(_jsonController.text) as Map<String, dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.t.pages.proxies.nodeBlacklist;
    return AlertDialog(
      title: Text(labels.editRule),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(labels.form)),
                ButtonSegment(value: false, label: Text(labels.editor)),
              ],
              selected: {_formMode},
              onSelectionChanged: (selection) {
                setState(() => _formMode = selection.single);
              },
              showSelectedIcon: false,
            ),
            const SizedBox(height: 12),
            if (_formMode) ...[
              TextField(
                controller: _nameController,
                decoration: InputDecoration(labelText: labels.ruleName),
              ),
              DropdownButtonFormField<NodeBlacklistMatchMode>(
                initialValue: _matchMode,
                decoration: InputDecoration(labelText: labels.matchMode),
                items: NodeBlacklistMatchMode.values
                    .map((mode) => DropdownMenuItem(value: mode, child: Text(mode.name)))
                    .toList(),
                onChanged: (value) => setState(() => _matchMode = value ?? NodeBlacklistMatchMode.any),
              ),
              DropdownButtonFormField<NodeBlacklistField>(
                initialValue: _field,
                decoration: InputDecoration(labelText: labels.field),
                items: NodeBlacklistField.values
                    .map((field) => DropdownMenuItem(value: field, child: Text(field.name)))
                    .toList(),
                onChanged: (value) => setState(() => _field = value ?? NodeBlacklistField.countryCode),
              ),
              DropdownButtonFormField<NodeBlacklistOperator>(
                initialValue: _operator,
                decoration: InputDecoration(labelText: labels.operator),
                items: NodeBlacklistOperator.values
                    .map((operator) => DropdownMenuItem(value: operator, child: Text(operator.name)))
                    .toList(),
                onChanged: (value) => setState(() => _operator = value ?? NodeBlacklistOperator.equals),
              ),
              TextField(
                controller: _valueController,
                decoration: InputDecoration(labelText: labels.value),
              ),
            ] else
              TextField(
                controller: _jsonController,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'JSON', border: OutlineInputBorder()),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(labels.cancel)),
        FilledButton(
          onPressed: () {
            try {
              final rule = _formMode ? _buildFormRule() : _buildEditorRule();
              Navigator.of(context).pop(rule);
            } catch (_) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid JSON')));
            }
          },
          child: Text(labels.save),
        ),
      ],
    );
  }
}
