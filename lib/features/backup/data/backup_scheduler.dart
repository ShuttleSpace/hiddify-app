import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/platform/platform_capabilities.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/features/backup/data/backup_preferences.dart';
import 'package:hiddify/features/backup/data/backup_service.dart';
import 'package:hiddify/features/backup/data/webdav_backup_repository.dart';
import 'package:hiddify/features/backup/model/backup_target.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class BackupScheduler with AppLogger {
  BackupScheduler(this._ref) {
    _ref.listen(BackupPreferences.autoBackupEnabled, (previous, next) => _reschedule());
    _ref.listen(BackupPreferences.autoBackupIntervalDays, (previous, next) => _reschedule());
    _reschedule();
  }

  final Ref _ref;
  Timer? _timer;

  void _reschedule() {
    _timer?.cancel();
    if (!_ref.read(platformCapabilitiesProvider).supportsBackgroundBackup) return;
    if (!_ref.read(BackupPreferences.autoBackupEnabled)) return;

    _timer = Timer.periodic(const Duration(hours: 1), (_) => runIfDue());
    Future.microtask(runIfDue);
  }

  Future<void> runIfDue() async {
    if (!_ref.read(BackupPreferences.autoBackupEnabled)) return;
    final lastRun = _ref.read(BackupPreferences.lastAutoBackupAt);
    final intervalDays = _ref.read(BackupPreferences.autoBackupIntervalDays);
    if (lastRun != null && DateTime.now().toUtc().difference(lastRun.toUtc()).inDays < intervalDays) {
      return;
    }
    await runNow();
  }

  Future<void> runNow() async {
    try {
      final bytes = _encodeBackup();
      final target = _ref.read(BackupPreferences.autoBackupTarget);
      final name = 'hiddify-backup-${DateTime.now().millisecondsSinceEpoch}.json';

      switch (target) {
        case BackupTarget.local:
          await _writeLocal(name, bytes);
        case BackupTarget.webdav:
          final credentials = await _ref.read(webdavBackupRepositoryProvider).load();
          if (credentials == null || !credentials.isConfigured) {
            throw const FileSystemException('WebDAV is not configured');
          }
          await _ref.read(webdavBackupRepositoryProvider).upload(credentials, name, bytes);
      }

      await _ref.read(BackupPreferences.lastAutoBackupAt.notifier).update(DateTime.now().toUtc());
    } catch (error, stackTrace) {
      loggy.warning('automatic backup failed', error, stackTrace);
    }
  }

  Future<void> _writeLocal(String name, List<int> bytes) async {
    final directories = await _ref.read(appDirectoriesProvider.future);
    final directory = Directory('${directories.baseDir.path}/backups/auto');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes, flush: true);

    final backups = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    backups.sort((a, b) => b.path.compareTo(a.path));
    for (final oldBackup in backups.skip(10)) {
      await oldBackup.delete();
    }
  }

  Uint8List _encodeBackup() {
    final options = <String, dynamic>{};
    for (final entry in ConfigOptions.preferences.entries) {
      options[entry.key] = _ref.read(entry.value.notifier).raw();
    }
    final document = {
      'formatVersion': backupFormatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': _ref.read(appInfoProvider).valueOrNull?.version ?? 'unknown',
      'options': options,
    };
    return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(document)));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

final backupSchedulerProvider = Provider<BackupScheduler>((ref) {
  final scheduler = BackupScheduler(ref);
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
