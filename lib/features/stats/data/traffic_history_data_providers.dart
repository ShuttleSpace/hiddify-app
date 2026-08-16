import 'package:hiddify/core/db/provider/db_providers.dart';
import 'package:hiddify/features/stats/data/traffic_history_data_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'traffic_history_data_providers.g.dart';

@Riverpod(keepAlive: true)
TrafficHistoryDataSource trafficHistoryDataSource(TrafficHistoryDataSourceRef ref) {
  return TrafficHistoryDao(ref.watch(dbProvider));
}
