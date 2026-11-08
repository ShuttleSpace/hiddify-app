import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

List<OutboundGroup> resolveAllProxiesResult(Either<ProxyFailure, OutboundGroupList> event) =>
    event.getOrElse((failure) => throw failure).items;

final allProxiesOverviewProvider = StreamProvider<List<OutboundGroup>>((ref) {
  return ref.watch(proxyRepositoryProvider).watchActiveProxies().map(resolveAllProxiesResult);
});
