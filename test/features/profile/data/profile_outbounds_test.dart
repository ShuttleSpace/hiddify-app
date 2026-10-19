import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/profile_outbounds.dart';

/// The tags of the outbounds the editor keeps.
List<String> tagsOf(Map<String, dynamic> config) =>
    userOutbounds(config).map((outbound) => outbound['tag'] as String).toList();

void main() {
  group('userOutbounds', () {
    test('keeps the nodes the user added', () {
      final config = {
        'outbounds': [
          {'type': 'hysteria2', 'tag': '日本01'},
          {'type': 'vless', 'tag': '美国01'},
        ],
      };

      expect(tagsOf(config), ['日本01', '美国01']);
    });

    test('drops the outbounds the core builds itself', () {
      final config = {
        'outbounds': [
          {'type': 'selector', 'tag': 'select', 'outbounds': ['proxy']},
          {'type': 'balancer', 'tag': 'lowest'},
          {'type': 'balancer', 'tag': 'balance'},
          {'type': 'http', 'tag': 'proxy'},
          {'type': 'direct', 'tag': 'direct §hide§'},
          {'type': 'direct', 'tag': 'direct-fragment §hide§'},
        ],
      };

      expect(tagsOf(config), ['proxy']);
    });

    test('drops a direct outbound the user named themselves', () {
      final config = {
        'outbounds': [
          {'type': 'direct', 'tag': 'direct'},
          {'type': 'direct', 'tag': 'bypass §hide§'},
          {'type': 'http', 'tag': 'proxy'},
        ],
      };

      expect(tagsOf(config), ['proxy']);
    });

    test('keeps a node whose name only looks like a core one', () {
      final config = {
        'outbounds': [
          {'type': 'http', 'tag': 'direct-fallback'},
          {'type': 'http', 'tag': 'my direct'},
        ],
      };

      expect(tagsOf(config), ['direct-fallback', 'my direct']);
    });

    test('drops an outbound without a type', () {
      final config = {
        'outbounds': [
          {'tag': 'proxy'},
          {'type': 'http', 'tag': 'proxy'},
        ],
      };

      expect(tagsOf(config), ['proxy']);
    });

    test('a config without outbounds has none', () {
      expect(userOutbounds({'log': {}}), isEmpty);
    });
  });
}
