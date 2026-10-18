import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/data/node_blacklist_engine.dart';
import 'package:hiddify/features/proxy/model/node_blacklist.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

void main() {
  final hkRule = NodeBlacklistRule(
    enabled: true,
    name: 'HK',
    matchMode: NodeBlacklistMatchMode.any,
    conditions: const [
      NodeBlacklistCondition(
        field: NodeBlacklistField.countryCode,
        operator: NodeBlacklistOperator.equals,
        value: 'HK',
      ),
    ],
  );

  final nameRule = NodeBlacklistRule(
    enabled: true,
    name: 'Claude',
    matchMode: NodeBlacklistMatchMode.all,
    conditions: const [
      NodeBlacklistCondition(
        field: NodeBlacklistField.countryCode,
        operator: NodeBlacklistOperator.equals,
        value: 'HK',
      ),
      NodeBlacklistCondition(
        field: NodeBlacklistField.nodeName,
        operator: NodeBlacklistOperator.contains,
        value: 'Claude',
      ),
    ],
  );

  test('country and name matching work', () {
    final node = OutboundInfo(
      tag: 'Claude-HK',
      tagDisplay: 'Claude-HK',
      ipinfo: IpInfo(countryCode: 'HK', org: 'Test ASN'),
    );

    expect(isNodeBlacklisted(node, [hkRule]), isTrue);
    expect(isNodeBlacklisted(node, [nameRule]), isTrue);
  });

  test('provider policy resolves effective rules', () {
    final doc = NodeBlacklistDocument(
      version: 1,
      globalRules: [hkRule],
      providers: const {
        'p1': ProviderNodeBlacklist(
          policy: NodeBlacklistPolicy.customOnly,
          rules: [],
        ),
        'p2': ProviderNodeBlacklist(
          policy: NodeBlacklistPolicy.globalPlusCustom,
          rules: [],
        ),
      },
    );

    expect(effectiveRules(doc, 'p1'), isEmpty);
    expect(effectiveRules(doc, 'p2'), [hkRule]);
  });
}
