import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/model/node_blacklist.dart';

void main() {
  test('NodeBlacklistDocument JSON round-trips', () {
    final doc = NodeBlacklistDocument(
      version: 1,
      globalRules: [
        NodeBlacklistRule(
          enabled: true,
          name: 'Block Hong Kong',
          matchMode: NodeBlacklistMatchMode.any,
          conditions: const [
            NodeBlacklistCondition(field: NodeBlacklistField.countryCode, operator: NodeBlacklistOperator.equals, value: 'HK'),
          ],
        ),
      ],
      providers: const {
        'p1': ProviderNodeBlacklist(policy: NodeBlacklistPolicy.globalPlusCustom, rules: []),
      },
    );

    expect(NodeBlacklistDocument.fromJson(doc.toJson()).toJson(), doc.toJson());
  });
}
