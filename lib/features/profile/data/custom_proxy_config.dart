import 'dart:convert';

/// Builds a single-outbound sing-box configuration for a proxy the user typed in.
///
/// One outbound carrying every proxy protocol the app can speak between them, so
/// the generated file stays small and readable: the user is here to reach one
/// proxy, and a config that files it among a dozen unused ones makes editing it
/// later harder.
///
/// The extras that a plain proxy does not need are left off on purpose. There is
/// no routing to get wrong, and a config whose rules the user did not ask for is
/// harder to reason about when it misbehaves.
class CustomProxyConfig {
  const CustomProxyConfig({
    required this.name,
    required this.server,
    required this.serverPort,
    this.username,
    this.password,
    this.protocol = CustomProxyProtocol.socks,
  });

  /// What to call the proxy. Comes straight from the form, so a saved profile
  /// reads as the user named it rather than as an address.
  final String name;

  final String server;
  final int serverPort;
  final String? username;
  final String? password;
  final CustomProxyProtocol protocol;

  /// Returns the failure to show, or null when the input is usable.
  ///
  /// Ordering is deliberate: the address is what everything else depends on, so a
  /// mistake there is reported before one further down the form.
  static String? validate({required String server, required String serverPort, String? username, String? password}) {
    if (server.trim().isEmpty) return 'the server address is required';
    final port = int.tryParse(serverPort.trim());
    if (port == null || port < 1 || port > 65535) return 'the port must be between 1 and 65535';
    // Entering one half of a pair is a common slip when a password is cleared or a
    // username typed in a hurry; the proxy would refuse the connection with a
    // message about authentication, which says nothing about the missing half.
    if ((username?.trim().isNotEmpty ?? false) != (password?.trim().isNotEmpty ?? false)) {
      return 'username and password go together; fill in both or neither';
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    final auth = (username?.trim().isNotEmpty ?? false)
        ? {'username': username!.trim(), 'password': (password ?? '').trim()}
        : null;
    return {
      'log': {'level': 'warn'},
      'inbounds': [
        {'type': 'mixed', 'tag': 'mixed-in', 'listen': '127.0.0.1', 'listen_port': 12334},
      ],
      'outbounds': [
        {
          'type': protocol.wireName,
          'tag': 'proxy',
          'server': server.trim(),
          'server_port': serverPort,
          if (auth case final a?) ...auth,
        },
        {'type': 'direct', 'tag': 'direct'},
      ],
    };
  }

  String encode() => JsonEncoder.withIndent('  ').convert(toJson());
}

enum CustomProxyProtocol {
  socks('socks'),
  http('http');

  const CustomProxyProtocol(this.wireName);

  /// The sing-box outbound type. http covers both http and https CONNECT, which
  /// one proxy usually serves on both ports.
  final String wireName;
}