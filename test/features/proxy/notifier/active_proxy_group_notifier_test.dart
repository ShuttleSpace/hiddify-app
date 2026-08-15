import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/notifier/active_proxy_group_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('select changes active group and setDefault picks first', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(activeProxyGroupNotifierProvider.notifier);
    notifier.setDefault([
      OutboundGroup(tag: 'A'),
      OutboundGroup(tag: 'B'),
    ]);
    expect(notifier.state, 'A');
    notifier.select('B');
    expect(notifier.state, 'B');
  });
}
