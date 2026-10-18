import 'dart:convert';

import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int backupFormatVersion = 1;

Map<String, dynamic> createBackupDocument(WidgetRef ref) {
  final options = <String, dynamic>{};
  for (final entry in ConfigOptions.preferences.entries) {
    options[entry.key] = ref.read(entry.value.notifier).raw();
  }

  final version = ref.read(appInfoProvider).valueOrNull?.version ?? 'unknown';
  return {
    'formatVersion': backupFormatVersion,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'appVersion': version,
    'options': options,
  };
}

Future<void> restoreBackupDocument(WidgetRef ref, String input) async {
  final decoded = jsonDecode(input);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Backup root must be an object.');
  }
  if (decoded['formatVersion'] != backupFormatVersion) {
    throw const FormatException('Unsupported backup format version.');
  }
  final options = decoded['options'];
  if (options is! Map<String, dynamic>) {
    throw const FormatException('Backup options must be an object.');
  }

  for (final entry in ConfigOptions.preferences.entries) {
    final value = options[entry.key];
    if (value != null) {
      try {
        await ref.read(entry.value.notifier).updateRaw(value);
      } catch (error) {
        // A malformed individual option must not prevent the remaining
        // options from being restored.
        continue;
      }
    }
  }
}
