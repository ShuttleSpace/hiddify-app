import 'package:hiddify/features/proxy/model/proxy_search_result.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

List<ProxySearchResult> searchProxyGroups(
  List<OutboundGroup> groups,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return const [];

  final results = <ProxySearchResult>[];
  for (final group in groups) {
    for (final item in group.items) {
      if (group.tag.toLowerCase().contains(normalized) ||
          item.tag.toLowerCase().contains(normalized)) {
        results.add(
          ProxySearchResult(
            groupTag: group.tag,
            nodeTag: item.tag,
            delay: item.urlTestDelay,
          ),
        );
      }
    }
  }

  results.sort((a, b) {
    final groupCompare = a.groupTag.compareTo(b.groupTag);
    if (groupCompare != 0) return groupCompare;
    return a.nodeTag.compareTo(b.nodeTag);
  });
  return results;
}

String formatProxySearchDelay(int delay) {
  return delay > 0 ? '$delay ms' : '--';
}
