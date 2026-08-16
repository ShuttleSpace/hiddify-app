import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/stats/data/traffic_history_data_providers.dart';
import 'package:hiddify/features/stats/data/traffic_history_data_source.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TrafficHistoryCalendarDialog extends ConsumerStatefulWidget {
  const TrafficHistoryCalendarDialog({super.key});

  @override
  ConsumerState<TrafficHistoryCalendarDialog> createState() => _TrafficHistoryCalendarDialogState();
}

class _TrafficHistoryCalendarDialogState extends ConsumerState<TrafficHistoryCalendarDialog> {
  late DateTime _month;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final dataSource = ref.watch(trafficHistoryDataSourceProvider);
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingEmpty = first.weekday % 7;
    final weekdays = MaterialLocalizations.of(context).narrowWeekdays;

    return AlertDialog(
      title: Text(t.pages.settings.traffic.historyCalendarTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: t.pages.settings.traffic.previousMonth,
                ),
                Expanded(
                  child: Text(
                    '${_month.year}-${_month.month.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: t.pages.settings.traffic.nextMonth,
                ),
              ],
            ),
            const Gap(8),
            StreamBuilder<List<DailyTrafficEntry>>(
              stream: dataSource.watchMonthlyUsage(month: _month),
              builder: (context, snapshot) {
                final entries = snapshot.data ?? const <DailyTrafficEntry>[];
                final byDay = {for (final entry in entries) entry.day: entry};
                final maxTotal = entries.fold<int>(
                  0,
                  (max, entry) => (entry.upload + entry.download) > max ? entry.upload + entry.download : max,
                );
                final selectedEntry = _selected == null ? null : byDay[dayKey(_selected!)];

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Text(
                              weekdays[i],
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                    const Gap(4),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: leadingEmpty + daysInMonth,
                      itemBuilder: (context, index) {
                        if (index < leadingEmpty) return const SizedBox.shrink();
                        final day = DateTime(_month.year, _month.month, index - leadingEmpty + 1);
                        final entry = byDay[dayKey(day)];
                        final total = entry == null ? 0 : entry.upload + entry.download;
                        final isSelected = _selected != null &&
                            _selected!.year == day.year &&
                            _selected!.month == day.month &&
                            _selected!.day == day.day;
                        final background = entry == null || maxTotal == 0
                            ? null
                            : Color.lerp(
                                theme.colorScheme.surfaceContainerHighest,
                                theme.colorScheme.primaryContainer,
                                (total / maxTotal).clamp(0.05, 1.0),
                              );
                        return InkWell(
                          onTap: () => setState(() => _selected = day),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: background,
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected ? Border.all(color: theme.colorScheme.primary, width: 2) : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${day.day}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: entry == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
                                fontWeight: entry == null ? FontWeight.w400 : FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const Gap(12),
                    if (selectedEntry == null)
                      Text(
                        _selected == null ? t.pages.settings.traffic.selectDay : t.pages.settings.traffic.noTrafficForDay,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('↑ ${selectedEntry.upload.size()}'),
                          const Gap(12),
                          Text('↓ ${selectedEntry.download.size()}'),
                        ],
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.common.close)),
      ],
    );
  }
}
