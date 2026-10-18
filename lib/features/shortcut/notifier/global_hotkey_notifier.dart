import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/shortcut/model/global_shortcut_action.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GlobalHotkeyState {
  const GlobalHotkeyState({this.enabled = false, this.failedActions = const {}});

  final bool enabled;
  final Set<GlobalShortcutAction> failedActions;

  GlobalHotkeyState copyWith({bool? enabled, Set<GlobalShortcutAction>? failedActions}) {
    return GlobalHotkeyState(enabled: enabled ?? this.enabled, failedActions: failedActions ?? this.failedActions);
  }
}

class GlobalHotkeyNotifier extends StateNotifier<GlobalHotkeyState> {
  GlobalHotkeyNotifier(this._ref) : super(const GlobalHotkeyState()) {
    if (_ref.read(Preferences.enableGlobalHotkeys)) {
      Future.microtask(() => setEnabled(true));
    }
  }

  final Ref _ref;

  Future<void> setEnabled(bool value) async {
    if (value) {
      final failed = await _registerAll();
      state = GlobalHotkeyState(enabled: true, failedActions: failed);
    } else {
      await hotKeyManager.unregisterAll();
      state = const GlobalHotkeyState(enabled: false);
    }
    await _ref.read(Preferences.enableGlobalHotkeys.notifier).update(value);
  }

  Future<Set<GlobalShortcutAction>> _registerAll() async {
    await hotKeyManager.unregisterAll();
    final failed = <GlobalShortcutAction>{};
    for (final binding in _defaultBindings) {
      try {
        final hotKey = _hotKeyFor(binding.action);
        await hotKeyManager.register(hotKey, keyDownHandler: (_) => _dispatch(binding.action));
      } catch (_) {
        failed.add(binding.action);
      }
    }
    return failed;
  }

  HotKey _hotKeyFor(GlobalShortcutAction action) {
    final raw = switch (action) {
      GlobalShortcutAction.toggleConnection => _ref.read(Preferences.globalHotkeyToggleConnection),
      GlobalShortcutAction.showWindow => _ref.read(Preferences.globalHotkeyShowWindow),
      GlobalShortcutAction.cycleServiceMode => _ref.read(Preferences.globalHotkeyCycleServiceMode),
    };
    if (raw == null) return _defaultBindings.firstWhere((binding) => binding.action == action).hotKey;
    try {
      return HotKey.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return _defaultBindings.firstWhere((binding) => binding.action == action).hotKey;
    }
  }

  Future<void> updateHotKey(GlobalShortcutAction action, HotKey hotKey) async {
    final raw = jsonEncode(hotKey.toJson());
    await switch (action) {
      GlobalShortcutAction.toggleConnection => _ref.read(Preferences.globalHotkeyToggleConnection.notifier).update(raw),
      GlobalShortcutAction.showWindow => _ref.read(Preferences.globalHotkeyShowWindow.notifier).update(raw),
      GlobalShortcutAction.cycleServiceMode => _ref.read(Preferences.globalHotkeyCycleServiceMode.notifier).update(raw),
    };
    if (state.enabled) {
      final failed = await _registerAll();
      state = GlobalHotkeyState(enabled: true, failedActions: failed);
    }
  }

  HotKey currentHotKey(GlobalShortcutAction action) => _hotKeyFor(action);

  Future<void> _dispatch(GlobalShortcutAction action) async {
    switch (action) {
      case GlobalShortcutAction.toggleConnection:
        await _ref.read(connectionNotifierProvider.notifier).toggleConnection();
      case GlobalShortcutAction.showWindow:
        await _ref.read(windowNotifierProvider.notifier).showOrHide();
      case GlobalShortcutAction.cycleServiceMode:
        final current = _ref.read(ConfigOptions.serviceMode);
        final values = ServiceMode.values;
        final next = values[(values.indexOf(current) + 1) % values.length];
        await _ref.read(ConfigOptions.serviceMode.notifier).update(next);
    }
  }
}

final globalHotkeyNotifierProvider = StateNotifierProvider<GlobalHotkeyNotifier, GlobalHotkeyState>(
  (ref) => GlobalHotkeyNotifier(ref),
);

class _HotkeyBinding {
  const _HotkeyBinding(this.action, this.hotKey);

  final GlobalShortcutAction action;
  final HotKey hotKey;
}

final _defaultBindings = <_HotkeyBinding>[
  _HotkeyBinding(
    GlobalShortcutAction.toggleConnection,
    HotKey(key: PhysicalKeyboardKey.keyH, modifiers: const [HotKeyModifier.control, HotKeyModifier.alt]),
  ),
  _HotkeyBinding(
    GlobalShortcutAction.showWindow,
    HotKey(
      key: PhysicalKeyboardKey.keyH,
      modifiers: const [HotKeyModifier.control, HotKeyModifier.alt, HotKeyModifier.shift],
    ),
  ),
  _HotkeyBinding(
    GlobalShortcutAction.cycleServiceMode,
    HotKey(key: PhysicalKeyboardKey.keyS, modifiers: const [HotKeyModifier.control, HotKeyModifier.alt]),
  ),
];
