import 'dart:async';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/stats/data/traffic_history_data_providers.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'traffic_history_recorder.g.dart';

@Riverpod(keepAlive: true)
class TrafficHistoryRecorder extends _$TrafficHistoryRecorder with AppLogger {
  SystemInfo _last = SystemInfo.create();
  int _pendingUpload = 0;
  int _pendingDownload = 0;
  String? _profileId;
  Timer? _flushTimer;

  @override
  void build() {
    ref.listen(activeProfileProvider, (previous, next) {
      _profileId = next.valueOrNull?.id;
    });

    ref.listen(serviceRunningProvider, (previous, next) {
      if (!next) {
        flush();
      } else {
        _last = SystemInfo.create();
      }
    });

    ref.listen(statsNotifierProvider, (previous, next) {
      final info = next.asData?.value;
      if (info != null) _account(info);
    });

    _flushTimer = Timer.periodic(const Duration(minutes: 1), (_) => flush());

    ref.onDispose(() {
      _flushTimer?.cancel();
      _flushTimer = null;
    });
  }

  void _account(SystemInfo info) {
    final uploadTotal = info.uplinkTotal.toInt();
    final downloadTotal = info.downlinkTotal.toInt();
    final lastUpload = _last.uplinkTotal.toInt();
    final lastDownload = _last.downlinkTotal.toInt();

    if (uploadTotal < lastUpload || downloadTotal < lastDownload) {
      _last = info;
      return;
    }

    _pendingUpload += uploadTotal - lastUpload;
    _pendingDownload += downloadTotal - lastDownload;
    _last = info;
  }

  Future<void> flush() async {
    if (!ref.read(Preferences.recordTrafficHistory)) return;
    final upload = _pendingUpload;
    final download = _pendingDownload;
    _pendingUpload = 0;
    _pendingDownload = 0;

    if (upload <= 0 && download <= 0) return;

    try {
      await ref
          .read(trafficHistoryDataSourceProvider)
          .addTraffic(day: DateTime.now(), upload: upload, download: download, profileId: _profileId);
      final retentionMonths = ref.read(Preferences.trafficHistoryRetentionMonths);
      final cutoff = DateTime.now().subtract(Duration(days: retentionMonths * 30));
      await ref.read(trafficHistoryDataSourceProvider).pruneBefore(cutoff);
    } catch (error, stackTrace) {
      loggy.warning('error flushing traffic history', error, stackTrace);
      _pendingUpload += upload;
      _pendingDownload += download;
    }
  }
}
