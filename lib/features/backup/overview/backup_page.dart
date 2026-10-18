import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/platform/platform_capabilities.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/backup/data/backup_preferences.dart';
import 'package:hiddify/features/backup/data/backup_scheduler.dart';
import 'package:hiddify/features/backup/data/backup_service.dart';
import 'package:hiddify/features/backup/data/webdav_backup_repository.dart';
import 'package:hiddify/features/backup/model/backup_target.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class BackupPage extends HookConsumerWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final webdav = ref.watch(webdavCredentialsProvider);
    final webdavCredentials = webdav.valueOrNull;
    final configured = webdavCredentials?.isConfigured ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.backup.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _LocalBackupCard(ref: ref),
          const Gap(16),
          _SettingsDataCard(ref: ref),
          const Gap(16),
          _AutoBackupCard(ref: ref),
          const Gap(16),
          if (ref.watch(platformCapabilitiesProvider).supportsSecureStorage)
            _WebdavBackupCard(ref: ref, state: webdav, configured: configured),
        ],
      ),
    );
  }
}

class _LocalBackupCard extends ConsumerWidget {
  const _LocalBackupCard({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final backupDirectory = ref.watch(BackupPreferences.localBackupDirectory);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.pages.settings.backup.local, style: Theme.of(context).textTheme.titleMedium),
            const Gap(4),
            Text(t.pages.settings.backup.localMsg),
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    backupDirectory ?? t.pages.settings.backup.directoryNotSet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: backupDirectory == null
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final directory = await FilePicker.platform.getDirectoryPath();
                    if (directory == null) return;
                    await ref.read(BackupPreferences.localBackupDirectory.notifier).update(directory);
                  },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(t.pages.settings.backup.chooseDirectory),
                ),
                if (backupDirectory != null)
                  IconButton(
                    tooltip: t.common.clear,
                    onPressed: () => ref.read(BackupPreferences.localBackupDirectory.notifier).reset(),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const Gap(8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _createLocalBackup(ref),
                    icon: const Icon(Icons.save_alt_rounded),
                    label: Text(t.pages.settings.backup.create),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _restoreLocalBackup(ref),
                    icon: const Icon(Icons.settings_backup_restore_rounded),
                    label: Text(t.pages.settings.backup.restore),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsDataCard extends ConsumerWidget {
  const _SettingsDataCard({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final notifier = ref.read(configOptionNotifierProvider.notifier);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.pages.settings.backup.settingsData, style: Theme.of(context).textTheme.titleMedium),
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _confirmImport(context, ref, notifier.importFromClipboard),
                  icon: const Icon(Icons.content_paste_rounded),
                  label: Text(t.pages.settings.options.import.clipboard),
                ),
                OutlinedButton.icon(
                  onPressed: () => _confirmImport(context, ref, notifier.importFromJsonFile),
                  icon: const Icon(Icons.file_open_rounded),
                  label: Text(t.pages.settings.options.import.file),
                ),
                OutlinedButton.icon(
                  onPressed: notifier.exportJsonClipboard,
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(t.pages.settings.options.export.anonymousToClipboard),
                ),
                OutlinedButton.icon(
                  onPressed: notifier.exportJsonFile,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(t.pages.settings.options.export.anonymousToFile),
                ),
                OutlinedButton.icon(
                  onPressed: () => notifier.exportJsonClipboard(excludePrivate: false),
                  icon: const Icon(Icons.copy_all_rounded),
                  label: Text(t.pages.settings.options.export.allToClipboard),
                ),
                OutlinedButton.icon(
                  onPressed: () => notifier.exportJsonFile(excludePrivate: false),
                  icon: const Icon(Icons.save_alt_rounded),
                  label: Text(t.pages.settings.options.export.allToFile),
                ),
                TextButton.icon(
                  onPressed: () => _confirmReset(context, ref, notifier.resetOption),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(t.pages.settings.options.reset),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmImport(BuildContext context, WidgetRef ref, Future<bool> Function() action) async {
    final t = ref.read(translationsProvider).requireValue;
    final confirmed = await ref
        .read(dialogNotifierProvider.notifier)
        .showConfirmation(title: t.common.msg.import.confirm, message: t.dialogs.confirmation.settings.import.msg);
    if (confirmed) await action();
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    final t = ref.read(translationsProvider).requireValue;
    final confirmed = await ref
        .read(dialogNotifierProvider.notifier)
        .showConfirmation(title: t.pages.settings.options.reset, message: t.dialogs.confirmation.settings.import.msg);
    if (confirmed) await action();
  }
}

class _AutoBackupCard extends ConsumerWidget {
  const _AutoBackupCard({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    ref.watch(backupSchedulerProvider);
    final enabled = ref.watch(BackupPreferences.autoBackupEnabled);
    final interval = ref.watch(BackupPreferences.autoBackupIntervalDays);
    final target = ref.watch(BackupPreferences.autoBackupTarget);
    final lastRun = ref.watch(BackupPreferences.lastAutoBackupAt);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.pages.settings.backup.automatic, style: Theme.of(context).textTheme.titleMedium),
            const Gap(8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(t.pages.settings.backup.enable),
              value: enabled,
              onChanged: ref.read(BackupPreferences.autoBackupEnabled.notifier).update,
            ),
            DropdownButtonFormField<int>(
              initialValue: interval,
              decoration: InputDecoration(labelText: t.pages.settings.backup.interval),
              items: const [1, 3, 7, 14, 30]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(t.pages.settings.backup.days(n: value)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref.read(BackupPreferences.autoBackupIntervalDays.notifier).update(value);
                }
              },
            ),
            const Gap(8),
            DropdownButtonFormField<BackupTarget>(
              initialValue: target,
              decoration: InputDecoration(labelText: t.pages.settings.backup.target),
              items: BackupTarget.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(
                        value == BackupTarget.local ? t.pages.settings.backup.local : t.pages.settings.backup.webdav,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref.read(BackupPreferences.autoBackupTarget.notifier).update(value);
                }
              },
            ),
            const Gap(8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    lastRun == null
                        ? t.pages.settings.backup.neverRun
                        : t.pages.settings.backup.lastRun(time: lastRun.toLocal()),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => ref.read(backupSchedulerProvider).runNow(),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(t.pages.settings.backup.runNow),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WebdavBackupCard extends ConsumerWidget {
  const _WebdavBackupCard({required this.ref, required this.state, required this.configured});

  final WidgetRef ref;
  final AsyncValue<WebdavCredentials?> state;
  final bool configured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final credentials = state.valueOrNull;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined),
                const Gap(8),
                Text(t.pages.settings.backup.webdav, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Gap(8),
            if (state.isLoading)
              const LinearProgressIndicator()
            else if (configured && credentials != null)
              Text('${credentials.url}\nUser: ${credentials.username}')
            else
              Text(t.pages.settings.backup.noWebdav),
            const Gap(12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _editWebdav(context, ref, credentials),
                  icon: const Icon(Icons.edit_rounded),
                  label: Text(configured ? t.pages.settings.backup.edit : t.pages.settings.backup.connect),
                ),
                if (configured && credentials != null) ...[
                  OutlinedButton.icon(
                    onPressed: () => _testWebdav(ref, credentials),
                    icon: const Icon(Icons.wifi_tethering_rounded),
                    label: Text(t.pages.settings.backup.test),
                  ),
                  FilledButton.icon(
                    onPressed: () => _uploadWebdav(ref, credentials),
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: Text(t.pages.settings.backup.upload),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _restoreWebdav(context, ref, credentials),
                    icon: const Icon(Icons.cloud_download_rounded),
                    label: Text(t.pages.settings.backup.restore),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await ref.read(webdavBackupRepositoryProvider).clear();
                      ref.invalidate(webdavCredentialsProvider);
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(t.pages.settings.backup.remove),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _createLocalBackup(WidgetRef ref) async {
  final t = ref.read(translationsProvider).requireValue;
  try {
    final bytes = _backupBytes(ref);
    final configuredDirectory = ref.read(BackupPreferences.localBackupDirectory);
    final name = 'hiddify-backup-${DateTime.now().millisecondsSinceEpoch}.json';

    if (configuredDirectory != null && configuredDirectory.isNotEmpty) {
      final directory = Directory(configuredDirectory);
      if (!await directory.exists()) await directory.create(recursive: true);
      await File('${directory.path}/$name').writeAsBytes(bytes, flush: true);
    } else {
      final path = await FilePicker.platform.saveFile(
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['json', 'hiddifybackup'],
        bytes: bytes,
      );
      if (path == null) return;
      final file = File(path);
      if (!await file.parent.exists()) await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.settings.backup.created);
  } catch (_) {
    ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.settings.backup.createFailed);
  }
}

Future<void> _restoreLocalBackup(WidgetRef ref) async {
  final t = ref.read(translationsProvider).requireValue;
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'hiddifybackup'],
    );
    final file = result?.files.single;
    if (file == null) return;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    await restoreBackupDocument(ref, utf8.decode(bytes));
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.settings.backup.restored);
  } catch (_) {
    ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.settings.backup.restoreFailed);
  }
}

Future<void> _editWebdav(BuildContext context, WidgetRef ref, WebdavCredentials? current) async {
  final t = ref.read(translationsProvider).requireValue;
  final urlController = TextEditingController(text: current?.url ?? '');
  final usernameController = TextEditingController(text: current?.username ?? '');
  final passwordController = TextEditingController(text: current?.password ?? '');

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.pages.settings.backup.webdav),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: urlController,
            decoration: const InputDecoration(labelText: 'URL'),
            keyboardType: TextInputType.url,
          ),
          TextField(
            controller: usernameController,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          TextField(
            controller: passwordController,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.common.cancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(t.common.save)),
      ],
    ),
  );

  if (saved != true) return;
  try {
    final credentials = WebdavCredentials(
      url: urlController.text,
      username: usernameController.text,
      password: passwordController.text,
    );
    final repository = ref.read(webdavBackupRepositoryProvider);
    await repository.testConnection(credentials);
    await repository.save(credentials);
    ref.invalidate(webdavCredentialsProvider);
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.settings.backup.connected);
  } catch (_) {
    ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.settings.backup.connectionFailed);
  }
}

Future<void> _testWebdav(WidgetRef ref, WebdavCredentials credentials) async {
  final t = ref.read(translationsProvider).requireValue;
  try {
    await ref.read(webdavBackupRepositoryProvider).testConnection(credentials);
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.settings.backup.connectionWorks);
  } catch (_) {
    ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.settings.backup.connectionFailed);
  }
}

Future<void> _uploadWebdav(WidgetRef ref, WebdavCredentials credentials) async {
  final t = ref.read(translationsProvider).requireValue;
  try {
    final bytes = _backupBytes(ref);
    final name = 'hiddify-backup-${DateTime.now().millisecondsSinceEpoch}.json';
    await ref.read(webdavBackupRepositoryProvider).upload(credentials, name, bytes);
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.settings.backup.uploaded);
  } catch (_) {
    ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.settings.backup.uploadFailed);
  }
}

Future<void> _restoreWebdav(BuildContext context, WidgetRef ref, WebdavCredentials credentials) async {
  final t = ref.read(translationsProvider).requireValue;
  try {
    final files = await ref.read(webdavBackupRepositoryProvider).list(credentials);
    if (files.isEmpty) {
      ref.read(inAppNotificationControllerProvider).showInfoToast(t.pages.settings.backup.noRemote);
      return;
    }
    if (!context.mounted) return;
    final selected = await showDialog<RemoteBackupFile>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(t.pages.settings.backup.selectRemote),
        children: [
          for (final file in files)
            SimpleDialogOption(onPressed: () => Navigator.of(context).pop(file), child: Text(file.name)),
        ],
      ),
    );
    if (selected == null) return;
    final bytes = await ref.read(webdavBackupRepositoryProvider).download(credentials, selected.url);
    await restoreBackupDocument(ref, utf8.decode(bytes));
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.settings.backup.remoteRestored);
  } catch (_) {
    ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.settings.backup.restoreFailed);
  }
}

Uint8List _backupBytes(WidgetRef ref) {
  final document = createBackupDocument(ref);
  return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(document)));
}
