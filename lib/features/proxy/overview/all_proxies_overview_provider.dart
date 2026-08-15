import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final allProxiesOverviewProvider = StreamProvider<List<OutboundGroup>>((ref) {
  return ref.watch(proxyRepositoryProvider).watchActiveProxies().map(
        (event) => event.getOrElse((_) => const <OutboundGroup>[]),
      );
});
