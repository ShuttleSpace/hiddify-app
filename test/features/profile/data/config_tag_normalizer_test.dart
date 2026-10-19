import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/config_tag_normalizer.dart';

/// The tags of the outbounds and endpoints of a config.
List<String> tagsOf(String content) {
  final decoded = jsonDecode(content) as Map<String, dynamic>;
  return [
    ...(decoded['outbounds'] as List? ?? []).map((o) => (o as Map)['tag'] as String),
    ...(decoded['endpoints'] as List? ?? []).map((e) => (e as Map)['tag'] as String),
  ];
}

void main() {
  group('ConfigTagNormalizer', () {
    test('renames the second node that shares a tag', () {
      final normalized = ConfigTagNormalizer.normalize(
        jsonEncode({
          'outbounds': [
            {'type': 'http', 'tag': 'proxy', 'server': 'a.example.com'},
            {'type': 'http', 'tag': 'proxy', 'server': 'b.example.com'},
          ],
        }),
      );

      expect(tagsOf(normalized), ['proxy', 'proxy 2']);
    });

    test('keeps every node when several share a tag', () {
      final normalized = ConfigTagNormalizer.normalize(
        jsonEncode({
          'outbounds': [
            {'type': 'http', 'tag': 'proxy'},
            {'type': 'http', 'tag': 'proxy'},
            {'type': 'http', 'tag': 'proxy'},
          ],
        }),
      );

      expect(tagsOf(normalized), ['proxy', 'proxy 2', 'proxy 3']);
    });

    test('leaves a config with unique tags alone', () {
      final content = jsonEncode({
        'outbounds': [
          {'type': 'http', 'tag': 'proxy'},
          {'type': 'direct', 'tag': 'direct'},
        ],
      });

      expect(ConfigTagNormalizer.normalize(content), content);
    });

    test('renames an endpoint that shares the tag of an outbound', () {
      final normalized = ConfigTagNormalizer.normalize(
        jsonEncode({
          'outbounds': [
            {'type': 'http', 'tag': 'proxy'},
          ],
          'endpoints': [
            {'type': 'wireguard', 'tag': 'proxy'},
          ],
        }),
      );

      expect(tagsOf(normalized), ['proxy', 'proxy 2']);
    });

    test('a selector that names both nodes follows the rename', () {
      final normalized = ConfigTagNormalizer.normalize(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'select', 'outbounds': ['proxy', 'proxy']},
            {'type': 'http', 'tag': 'proxy'},
            {'type': 'http', 'tag': 'proxy'},
          ],
        }),
      );

      final decoded = jsonDecode(normalized) as Map<String, dynamic>;
      final outbounds = decoded['outbounds'] as List;
      expect((outbounds[0] as Map)['outbounds'], ['proxy', 'proxy 2']);
    });

    test('a name that is already taken is not reused', () {
      final normalized = ConfigTagNormalizer.normalize(
        jsonEncode({
          'outbounds': [
            {'type': 'http', 'tag': 'proxy'},
            {'type': 'http', 'tag': 'proxy 2'},
            {'type': 'http', 'tag': 'proxy'},
          ],
        }),
      );

      expect(tagsOf(normalized), ['proxy', 'proxy 2', 'proxy 3']);
    });

    test('a config that is a list of outbounds is fixed too', () {
      final normalized = ConfigTagNormalizer.normalize(
        jsonEncode([
          {'type': 'http', 'tag': 'proxy'},
          {'type': 'http', 'tag': 'proxy'},
        ]),
      );

      final decoded = jsonDecode(normalized) as List;
      expect(decoded.map((o) => (o as Map)['tag']), ['proxy', 'proxy 2']);
    });

    test('content that is not a config is left alone', () {
      const links = 'vless://uuid@example.com:443#node\nvmess://uuid@example.com:443#node';
      expect(ConfigTagNormalizer.normalize(links), links);
    });

    test('a node without a tag is left alone', () {
      final normalized = ConfigTagNormalizer.normalize(
        jsonEncode({
          'outbounds': [
            {'type': 'http'},
            {'type': 'http'},
          ],
        }),
      );

      final decoded = jsonDecode(normalized) as Map<String, dynamic>;
      expect((decoded['outbounds'] as List).length, 2);
    });
  });
}
