import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/shortcut/model/global_shortcut_action.dart';
import 'package:hiddify/features/shortcut/notifier/global_hotkey_notifier.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ShortcutsPage extends HookConsumerWidget {
  const ShortcutsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final globalHotkeys = ref.watch(globalHotkeyNotifierProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.shortcuts.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!PlatformUtils.isDesktop)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(padding: const EdgeInsets.all(16), child: Text(t.pages.settings.shortcuts.mobileMsg)),
            ),
          const Gap(8),
          if (PlatformUtils.isDesktop) ...[
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    title: Text(t.pages.settings.shortcuts.globalHotkeys),
                    subtitle: Text(t.pages.settings.shortcuts.globalHotkeysMsg),
                    value: globalHotkeys.enabled,
                    onChanged: (value) => ref.read(globalHotkeyNotifierProvider.notifier).setEnabled(value),
                  ),
                  if (globalHotkeys.enabled) ...[
                    const Divider(height: 1),
                    _EditableHotKeyRow(
                      action: t.pages.settings.shortcuts.toggleConnection,
                      hotKey: ref.read(globalHotkeyNotifierProvider.notifier).currentHotKey(GlobalShortcutAction.toggleConnection),
                      onSaved: (hotKey) => ref
                          .read(globalHotkeyNotifierProvider.notifier)
                          .updateHotKey(GlobalShortcutAction.toggleConnection, hotKey),
                    ),
                    const Divider(height: 1),
                    _EditableHotKeyRow(
                      action: t.pages.settings.shortcuts.openSettings,
                      hotKey: ref.read(globalHotkeyNotifierProvider.notifier).currentHotKey(GlobalShortcutAction.showWindow),
                      onSaved: (hotKey) => ref
                          .read(globalHotkeyNotifierProvider.notifier)
                          .updateHotKey(GlobalShortcutAction.showWindow, hotKey),
                    ),
                    const Divider(height: 1),
                    _EditableHotKeyRow(
                      action: t.pages.settings.shortcuts.cycleMode,
                      hotKey: ref.read(globalHotkeyNotifierProvider.notifier).currentHotKey(GlobalShortcutAction.cycleServiceMode),
                      onSaved: (hotKey) => ref
                          .read(globalHotkeyNotifierProvider.notifier)
                          .updateHotKey(GlobalShortcutAction.cycleServiceMode, hotKey),
                    ),
                  ],
                  if (globalHotkeys.enabled && globalHotkeys.failedActions.isNotEmpty) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: Text(t.pages.settings.shortcuts.failed),
                      subtitle: Text(
                        globalHotkeys.failedActions
                            .map(
                              (action) => switch (action) {
                                GlobalShortcutAction.toggleConnection => t.pages.settings.shortcuts.toggleConnection,
                                GlobalShortcutAction.showWindow => t.pages.settings.shortcuts.openSettings,
                                GlobalShortcutAction.cycleServiceMode => t.pages.settings.shortcuts.cycleMode,
                              },
                            )
                            .join(', '),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Gap(16),
          ],
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _ShortcutRow(
                  action: t.pages.settings.shortcuts.toggleConnection,
                  shortcut: PlatformUtils.isMacOS ? '⌘T' : 'Ctrl+T',
                ),
                const Divider(height: 1),
                _ShortcutRow(
                  action: t.pages.settings.shortcuts.addClipboard,
                  shortcut: PlatformUtils.isMacOS ? '⌘V' : 'Ctrl+V',
                ),
                const Divider(height: 1),
                _ShortcutRow(action: t.pages.settings.shortcuts.cycleMode, shortcut: 'Ctrl+Shift+S'),
                const Divider(height: 1),
                _ShortcutRow(
                  action: t.pages.settings.shortcuts.openSettings,
                  shortcut: PlatformUtils.isMacOS ? '⌘,' : '',
                ),
                if (PlatformUtils.isMacOS) ...[
                  const Divider(height: 1),
                  _ShortcutRow(action: t.pages.settings.shortcuts.closeWindow, shortcut: '⌘W'),
                ],
                if (PlatformUtils.isLinux) ...[
                  const Divider(height: 1),
                  _ShortcutRow(action: t.pages.settings.shortcuts.quit, shortcut: 'Ctrl+Q'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableHotKeyRow extends StatelessWidget {
  const _EditableHotKeyRow({required this.action, required this.hotKey, required this.onSaved});

  final String action;
  final HotKey hotKey;
  final ValueChanged<HotKey> onSaved;

  Future<void> _record(BuildContext context) async {
    var next = hotKey;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action),
        content: HotKeyRecorder(
          initalHotKey: hotKey,
          onHotKeyRecorded: (value) => next = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (shouldSave == true) onSaved(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(action),
      trailing: InkWell(
        onTap: () => _record(context),
        borderRadius: BorderRadius.circular(8),
        child: HotKeyVirtualView(hotKey: hotKey),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.action, required this.shortcut});

  final String action;
  final String shortcut;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(action),
      trailing: shortcut.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(shortcut, style: Theme.of(context).textTheme.labelLarge),
            ),
    );
  }
}
