import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/backup/model/backup_target.dart';

abstract class BackupPreferences {
  static final autoBackupEnabled = PreferencesNotifier.create<bool, bool>('backup-auto-enabled', false);

  static final autoBackupIntervalDays = PreferencesNotifier.create<int, int>(
    'backup-auto-interval-days',
    7,
    validator: (value) => value >= 1 && value <= 90,
  );

  static final autoBackupTarget = PreferencesNotifier.create<BackupTarget, String>(
    'backup-auto-target',
    BackupTarget.local,
    mapFrom: BackupTarget.values.byName,
    mapTo: (value) => value.name,
  );

  static final localBackupDirectory = PreferencesNotifier.create<String?, String?>(
    'backup-local-directory',
    null,
    mapFrom: (value) => value == null || value.isEmpty ? null : value,
    mapTo: (value) => value ?? '',
  );

  static final lastAutoBackupAt = PreferencesNotifier.create<DateTime?, String?>(
    'backup-auto-last-run',
    null,
    mapFrom: (value) => value == null ? null : DateTime.tryParse(value),
    mapTo: (value) => value?.toUtc().toIso8601String(),
  );
}
