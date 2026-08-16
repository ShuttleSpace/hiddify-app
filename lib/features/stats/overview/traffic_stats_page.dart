import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/platform/platform_capabilities.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/features/stats/widget/traffic_history_calendar.dart';
import 'package:hiddify/features/stats/data/traffic_history_data_providers.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/features/stats/widget/stats_card.dart';
import 'package:hiddify/features/system_tray/model/tray_speed_layout.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TrafficStatsPage extends HookConsumerWidget {
  const TrafficStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final live = ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create();
    final dataSource = ref.watch(trafficHistoryDataSourceProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.traffic.title)),
      body: StreamBuilder<List<DailyTrafficEntry>>(
        stream: dataSource.watchDailyUsage(start: DateTime(DateTime.now().year - 1), end: DateTime.now()),
        builder: (context, snapshot) {
          final today = DateTime.now();
          final todayKey =
              '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
          final monthPrefix = todayKey.substring(0, 7);

          final entries = snapshot.data ?? const <DailyTrafficEntry>[];
          final todayUpload = entries.where((e) => e.day == todayKey).fold<int>(0, (sum, e) => sum + e.upload);
          final todayDownload = entries.where((e) => e.day == todayKey).fold<int>(0, (sum, e) => sum + e.download);
          final monthUpload = entries
              .where((e) => e.day.startsWith(monthPrefix))
              .fold<int>(0, (sum, e) => sum + e.upload);
          final monthDownload = entries
              .where((e) => e.day.startsWith(monthPrefix))
              .fold<int>(0, (sum, e) => sum + e.download);
          final allUpload = entries.fold<int>(0, (sum, e) => sum + e.upload);
          final allDownload = entries.fold<int>(0, (sum, e) => sum + e.download);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StatsCard(
                title: t.pages.settings.traffic.live,
                stats: [
                  (
                    label: Text(t.pages.settings.traffic.upload, style: const TextStyle(color: Colors.green)),
                    data: Text(live.uplink.toInt().speed()),
                    semanticLabel: null,
                  ),
                  (
                    label: Text(t.pages.settings.traffic.download, style: const TextStyle(color: Colors.red)),
                    data: Text(live.downlink.toInt().speed()),
                    semanticLabel: null,
                  ),
                ],
              ),
              const Gap(12),
              _HistoryCard(
                label: t.pages.settings.traffic.today,
                upload: todayUpload,
                download: todayDownload,
                uploadLabel: t.pages.settings.traffic.upload,
                downloadLabel: t.pages.settings.traffic.download,
              ),
              const Gap(8),
              _HistoryCard(
                label: t.pages.settings.traffic.thisMonth,
                upload: monthUpload,
                download: monthDownload,
                uploadLabel: t.pages.settings.traffic.upload,
                downloadLabel: t.pages.settings.traffic.download,
              ),
              const Gap(8),
              _HistoryCard(
                label: t.pages.settings.traffic.allRecorded,
                upload: allUpload,
                download: allDownload,
                uploadLabel: t.pages.settings.traffic.upload,
                downloadLabel: t.pages.settings.traffic.download,
              ),
              const Gap(16),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => const TrafficHistoryCalendarDialog(),
                ),
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(t.pages.settings.traffic.viewHistory),
              ),
              const Gap(16),
              SwitchListTile.adaptive(
                title: Text(t.pages.settings.traffic.recordHistory),
                value: ref.watch(Preferences.recordTrafficHistory),
                onChanged: ref.read(Preferences.recordTrafficHistory.notifier).update,
              ),
              if (ref.watch(Preferences.recordTrafficHistory))
                ListTile(
                  leading: const Icon(Icons.calendar_month_rounded),
                  title: Text(t.pages.settings.traffic.retention),
                  subtitle: Text(
                    t.pages.settings.traffic.retentionMonths(n: ref.watch(Preferences.trafficHistoryRetentionMonths)),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final value = await showDialog<int>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          t.pages.settings.traffic.retentionMonths(
                            n: ref.read(Preferences.trafficHistoryRetentionMonths),
                          ),
                        ),
                        content: DropdownButtonFormField<int>(
                          initialValue: ref.read(Preferences.trafficHistoryRetentionMonths),
                          items: const [1, 3, 6, 12, 18, 24, 36]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(t.pages.settings.traffic.retentionMonths(n: value)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => Navigator.of(context).pop(value),
                        ),
                      ),
                    );
                    if (value != null) {
                      await ref.read(Preferences.trafficHistoryRetentionMonths.notifier).update(value);
                    }
                  },
                ),
              if (ref.watch(platformCapabilitiesProvider).supportsTraySpeedIndicator)
                SwitchListTile.adaptive(
                  title: Text(t.pages.settings.traffic.showTraySpeed),
                  value: ref.watch(Preferences.showTraySpeedIndicator),
                  onChanged: ref.read(Preferences.showTraySpeedIndicator.notifier).update,
                ),
              if (ref.watch(platformCapabilitiesProvider).supportsTraySpeedIndicator &&
                  ref.watch(Preferences.showTraySpeedIndicator))
                ChoicePreferenceWidget(
                  selected: ref.watch(Preferences.traySpeedLayout),
                  preferences: ref.watch(Preferences.traySpeedLayout.notifier),
                  choices: TraySpeedLayout.values,
                  title: t.pages.settings.traffic.traySpeedLayout,
                  icon: Icons.view_agenda_rounded,
                  presentChoice: (value) => switch (value) {
                    TraySpeedLayout.horizontal => t.pages.settings.traffic.traySpeedLayoutHorizontal,
                    TraySpeedLayout.vertical => t.pages.settings.traffic.traySpeedLayoutVertical,
                  },
                ),
              const Gap(8),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await ref
                      .read(dialogNotifierProvider.notifier)
                      .showConfirmation(
                        title: t.pages.settings.traffic.clearHistory,
                        message: t.pages.settings.traffic.clearHistoryMsg,
                      );
                  if (confirmed) {
                    await ref.read(trafficHistoryDataSourceProvider).clear();
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(t.pages.settings.traffic.clearHistory),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.label,
    required this.upload,
    required this.download,
    required this.uploadLabel,
    required this.downloadLabel,
  });

  final String label;
  final int upload;
  final int download;
  final String uploadLabel;
  final String downloadLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const Gap(8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('$uploadLabel ${upload.size()}'), Text('$downloadLabel ${download.size()}')],
            ),
          ],
        ),
      ),
    );
  }
}
