import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/proxy/domain/proxy_search.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/proxy/overview/all_proxies_overview_provider.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

void main() {
  test('search matches node and group names case-insensitively', () {
    final groups = [
      OutboundGroup(
        tag: 'Auto',
        items: [OutboundInfo(tag: 'HK-01', urlTestDelay: 123)],
      ),
      OutboundGroup(
        tag: 'Manual',
        items: [OutboundInfo(tag: 'US-02', urlTestDelay: 0)],
      ),
    ];

    final result = searchProxyGroups(groups, 'hk');

    expect(result, hasLength(1));
    expect(result.single.groupTag, 'Auto');
    expect(result.single.nodeTag, 'HK-01');
  });

  test('delay formatting uses double dash for zero', () {
    expect(formatProxySearchDelay(0), '--');
    expect(formatProxySearchDelay(128), '128 ms');
  });

  test('resolveAllProxiesResult returns the list on success', () {
    final groups = [
      OutboundGroup(
        tag: 'Auto',
        items: [OutboundInfo(tag: 'HK-01', urlTestDelay: 123)],
      ),
    ];

    final result = resolveAllProxiesResult(right(groups));

    expect(result, same(groups));
  });

  test('resolveAllProxiesResult throws the failure', () {
    final failure = ProxyFailure.serviceNotRunning();

    expect(() => resolveAllProxiesResult(left(failure)), throwsA(same(failure)));
  });
}
