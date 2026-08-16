import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ShortcutWrapper extends HookConsumerWidget {
  const ShortcutWrapper(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: {
        // Android TV D-pad select support
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        if (!kIsWeb) ...{
          if (Platform.isLinux) ...{
            // quit app using Control+Q on Linux
            const SingleActivator(LogicalKeyboardKey.keyQ, control: true): QuitAppIntent(),
          },
          if (Platform.isMacOS) ...{
            // close window using Command+W on macOS
            const SingleActivator(LogicalKeyboardKey.keyW, meta: true): CloseWindowIntent(),

            // open settings using Command+, on macOS
            const SingleActivator(LogicalKeyboardKey.comma, meta: true): OpenSettingsIntent(),
          },
          if (Platform.isLinux) ...{
            const SingleActivator(LogicalKeyboardKey.keyT, control: true): ToggleConnectionIntent(),
          },
          if (Platform.isMacOS) ...{
            const SingleActivator(LogicalKeyboardKey.keyT, meta: true): ToggleConnectionIntent(),
          },
          if (Platform.isWindows) ...{
            const SingleActivator(LogicalKeyboardKey.keyT, control: true): ToggleConnectionIntent(),
          },
          const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): CycleServiceModeIntent(),
        },
        // try adding profile using Command+V and Control+V
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): PasteIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): PasteIntent(),
      },
      child: Actions(
        actions: {
          CloseWindowIntent: CallbackAction(
            onInvoke: (_) async {
              await ref.read(windowNotifierProvider.notifier).hide();
              return null;
            },
          ),
          QuitAppIntent: CallbackAction(
            onInvoke: (_) async {
              await ref.read(windowNotifierProvider.notifier).exit();
              return null;
            },
          ),
          OpenSettingsIntent: CallbackAction(
            onInvoke: (_) {
              if (rootNavKey.currentContext != null) {
                rootNavKey.currentContext!.goNamed('settings');
              }
              return null;
            },
          ),
          ToggleConnectionIntent: CallbackAction(
            onInvoke: (_) async {
              await ref.read(connectionNotifierProvider.notifier).toggleConnection();
              return null;
            },
          ),
          CycleServiceModeIntent: CallbackAction(
            onInvoke: (_) async {
              final current = ref.read(ConfigOptions.serviceMode);
              final values = ServiceMode.values;
              final next = values[(values.indexOf(current) + 1) % values.length];
              await ref.read(ConfigOptions.serviceMode.notifier).update(next);
              return null;
            },
          ),
          PasteIntent: CallbackAction(
            onInvoke: (_) async {
              if (rootNavKey.currentContext != null) {
                final captureResult = await Clipboard.getData(Clipboard.kTextPlain).then((value) => value?.text ?? '');
                ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(url: captureResult);
              }
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

class CloseWindowIntent extends Intent {}

class QuitAppIntent extends Intent {}

class OpenSettingsIntent extends Intent {}

class PasteIntent extends Intent {}

class ToggleConnectionIntent extends Intent {}

class CycleServiceModeIntent extends Intent {}
