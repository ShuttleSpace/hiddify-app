import 'package:drift/drift.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/utils/custom_loggers.dart';

part 'traffic_history_data_source.g.dart';

abstract interface class TrafficHistoryDataSource {
  Stream<List<DailyTrafficEntry>> watchDailyUsage({required DateTime start, required DateTime end});
  Stream<List<DailyTrafficEntry>> watchMonthlyUsage({required DateTime month});
  Future<void> addTraffic({required DateTime day, required int upload, required int download, String? profileId});
  Future<void> clear();
  Future<void> pruneBefore(DateTime date);
}

String dayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

@DriftAccessor(tables: [DailyTrafficEntries])
class TrafficHistoryDao extends DatabaseAccessor<Db>
    with _$TrafficHistoryDaoMixin, InfraLogger
    implements TrafficHistoryDataSource {
  TrafficHistoryDao(super.db);

  @override
  Stream<List<DailyTrafficEntry>> watchDailyUsage({required DateTime start, required DateTime end}) {
    final startKey = dayKey(start);
    final endKey = dayKey(end);
    return (select(dailyTrafficEntries)
          ..where((tbl) => tbl.day.isBiggerOrEqualValue(startKey) & tbl.day.isSmallerOrEqualValue(endKey))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.day)]))
        .watch();
  }

  @override
  Stream<List<DailyTrafficEntry>> watchMonthlyUsage({required DateTime month}) {
    final first = DateTime(month.year, month.month);
    final last = DateTime(month.year, month.month + 1, 0);
    return watchDailyUsage(start: first, end: last);
  }

  @override
  Future<void> addTraffic({
    required DateTime day,
    required int upload,
    required int download,
    String? profileId,
  }) async {
    if (upload <= 0 && download <= 0) return;
    await transaction(() async {
      final key = dayKey(day);
      Expression<bool> matchesProfile($DailyTrafficEntriesTable tbl) =>
          profileId == null ? tbl.profileId.isNull() : tbl.profileId.equals(profileId!);
      final existing = await (select(
        dailyTrafficEntries,
      )..where((tbl) => tbl.day.equals(key) & matchesProfile(tbl))).getSingleOrNull();
      if (existing == null) {
        await into(dailyTrafficEntries).insert(
          DailyTrafficEntriesCompanion.insert(
            day: key,
            profileId: Value(profileId),
            upload: Value(upload),
            download: Value(download),
          ),
        );
      } else {
        await (update(dailyTrafficEntries)..where((tbl) => tbl.day.equals(key) & matchesProfile(tbl))).write(
          DailyTrafficEntriesCompanion(
            upload: Value(existing.upload + upload),
            download: Value(existing.download + download),
          ),
        );
      }
    });
  }

  @override
  Future<void> clear() => delete(dailyTrafficEntries).go();

  @override
  Future<void> pruneBefore(DateTime date) async {
    await (delete(dailyTrafficEntries)..where((tbl) => tbl.day.isSmallerThanValue(dayKey(date)))).go();
  }
}
