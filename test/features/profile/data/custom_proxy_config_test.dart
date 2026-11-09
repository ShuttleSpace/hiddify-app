import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/custom_proxy_config.dart';

void main() {
  const config = CustomProxyConfig(
    name: 'office',
    server: 'proxy.example.com',
    serverPort: 8080,
    protocol: CustomProxyProtocol.http,
    username: 'me',
    password: 'secret',
  );

  test('a plain proxy carries only what it needs', () {
    final json = config.toJson();
    final outbound = (json['outbounds']! as List).first as Map<String, dynamic>;
    expect(outbound, {
      'type': 'http',
      'tag': 'proxy',
      'server': 'proxy.example.com',
      'server_port': 8080,
      'username': 'me',
      'password': 'secret',
    });
    expect(json['inbounds'], hasLength(1));
    expect(json.containsKey('route'), isFalse);
  });

  test('no authentication means no username key at all', () {
    final json = const CustomProxyConfig(name: 'anon', server: '10.0.0.2', serverPort: 1080).toJson();
    final outbound = (json['outbounds']! as List).first as Map<String, dynamic>;
    expect(outbound.containsKey('username'), isFalse);
    expect(outbound.containsKey('password'), isFalse);
  });

  test('the encoded config is valid JSON', () {
    final decoded = jsonDecode(config.encode());
    expect(decoded['outbounds'], isA<List<dynamic>>());
  });

  group('validate', () {
    test('accepts an address, a port and no credentials', () {
      expect(CustomProxyConfig.validate(server: 'a.example', serverPort: '443'), isNull);
    });

    test('rejects a missing address', () {
      expect(CustomProxyConfig.validate(server: '  ', serverPort: '443'), isNotNull);
    });

    test('rejects a port that is not a number', () {
      expect(CustomProxyConfig.validate(server: 'a.example', serverPort: 'https'), isNotNull);
    });

    test('rejects a port outside the range', () {
      expect(CustomProxyConfig.validate(server: 'a.example', serverPort: '0'), isNotNull);
      expect(CustomProxyConfig.validate(server: 'a.example', serverPort: '65536'), isNotNull);
    });

    test('rejects half a credential pair', () {
      expect(CustomProxyConfig.validate(server: 'a.example', serverPort: '443', username: 'me'), isNotNull);
      expect(CustomProxyConfig.validate(server: 'a.example', serverPort: '443', password: 'p'), isNotNull);
    });

    test('accepts both halves or neither', () {
      expect(
        CustomProxyConfig.validate(server: 'a.example', serverPort: '443', username: 'me', password: 'p'),
        isNull,
      );
    });
  });
}
