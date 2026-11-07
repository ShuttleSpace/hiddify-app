import 'dart:convert';
import 'dart:io';

import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/overview/all_proxies_overview_provider.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mcp_dart/mcp_dart.dart';

final mcpServerProvider =
    NotifierProvider<McpServerNotifier, void>(McpServerNotifier.new);

/// Runs a local MCP server (Streamable HTTP) inside the app process so that an
/// agent can control the connection while the app is running. The server binds
/// to the loopback address and requires a bearer token.
class McpServerNotifier extends Notifier<void> {
  StreamableMcpServer? _server;

  @override
  void build() {}

  Future<void> start({required int port, required String token}) async {
    if (_server != null) return;
    _server = StreamableMcpServer(
      serverFactory: (_) {
        final server = McpServer(
          const Implementation(name: 'hiddify', version: '1.0.0'),
          options: const McpServerOptions(),
        );
        _registerTools(server);
        return server;
      },
      host: '127.0.0.1',
      port: port,
      path: '/mcp',
      enableDnsRebindingProtection: true,
      allowedHosts: {'localhost', '127.0.0.1'},
      authenticationHandler: (request) {
        final req = request as HttpRequest;
        final auth = req.headers.value(HttpHeaders.authorizationHeader);
        if (auth != null &&
            auth.startsWith('Bearer ') &&
            auth.substring(7) == token) {
          return const StreamableMcpAuthenticationResult.allow();
        }
        return const StreamableMcpAuthenticationResult.unauthorized();
      },
    );
    await _server!.start();
  }

  Future<void> stop() async {
    await _server?.stop();
    _server = null;
  }

  void _registerTools(McpServer server) {
    server.registerTool(
      'hiddify_status',
      description:
          'Return connection state, active profile and current node as JSON.',
      inputSchema: JsonSchema.object(properties: const {}),
      callback: (args, extra) {
        final status = ref.read(connectionNotifierProvider).valueOrNull;
        final active = ref.read(activeProfileProvider).valueOrNull;
        final data = {
          'state': status?.when(
            disconnected: (_) => 'disconnected',
            connecting: () => 'connecting',
            connected: () => 'connected',
            disconnecting: () => 'disconnecting',
          ),
          'isConnected': status?.isConnected ?? false,
          'activeProfile': active == null
              ? null
              : {
                  'id': active.id,
                  'name': active.name,
                  'type': active.map(remote: (_) => 'remote', local: (_) => 'local'),
                  'active': active.active,
                },
        };
        return CallToolResult(content: [TextContent(text: jsonEncode(data))]);
      },
    );

    server.registerTool(
      'hiddify_connect',
      description: 'Connect using the active profile.',
      inputSchema: JsonSchema.object(properties: const {}),
      callback: (args, extra) async {
        final notifier = ref.read(connectionNotifierProvider.notifier);
        final status = ref.read(connectionNotifierProvider).valueOrNull;
        if (status == null || !status.isConnected) {
          await notifier.toggleConnection();
        }
        return CallToolResult(content: [TextContent(text: 'connected')]);
      },
    );

    server.registerTool(
      'hiddify_disconnect',
      description: 'Disconnect the core.',
      inputSchema: JsonSchema.object(properties: const {}),
      callback: (args, extra) async {
        final notifier = ref.read(connectionNotifierProvider.notifier);
        final status = ref.read(connectionNotifierProvider).valueOrNull;
        if (status != null && status.isConnected) {
          await notifier.toggleConnection();
        }
        return CallToolResult(content: [TextContent(text: 'disconnected')]);
      },
    );

    server.registerTool(
      'hiddify_toggle',
      description: 'Toggle the connection.',
      inputSchema: JsonSchema.object(properties: const {}),
      callback: (args, extra) async {
        await ref.read(connectionNotifierProvider.notifier).toggleConnection();
        return CallToolResult(content: [TextContent(text: 'toggled')]);
      },
    );

    server.registerTool(
      'hiddify_list_profiles',
      description: 'List all profiles (id, name, type, active) as JSON.',
      inputSchema: JsonSchema.object(properties: const {}),
      callback: (args, extra) {
        final profiles =
            ref.read(profilesNotifierProvider).valueOrNull ?? <ProfileEntity>[];
        final data = profiles
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'type': p.map(remote: (_) => 'remote', local: (_) => 'local'),
                'active': p.active,
              },
            )
            .toList();
        return CallToolResult(content: [TextContent(text: jsonEncode(data))]);
      },
    );

    server.registerTool(
      'hiddify_select_profile',
      description:
          'Select the active profile by id; reconnects if already connected.',
      inputSchema: JsonSchema.object(
        properties: {
          'profileId': JsonSchema.string(
            description: 'Profile id (uuid) from hiddify_list_profiles',
          ),
        },
        required: ['profileId'],
      ),
      callback: (args, extra) async {
        final id = args['profileId'] as String;
        await ref
            .read(profilesNotifierProvider.notifier)
            .selectActiveProfile(id);
        return CallToolResult(content: [TextContent(text: 'profile selected')]);
      },
    );

    server.registerTool(
      'hiddify_list_nodes',
      description: 'List proxy node groups and their nodes as JSON.',
      inputSchema: JsonSchema.object(properties: const {}),
      callback: (args, extra) {
        final groups =
            ref.read(allProxiesOverviewProvider).valueOrNull ?? [];
        final data = groups
            .map(
              (g) => {
                'tag': g.tag,
                'type': g.type,
                'items': g.items
                    .map(
                      (i) => {
                        'tag': i.tag,
                        'type': i.type,
                        'isSelected': i.isSelected,
                      },
                    )
                    .toList(),
              },
            )
            .toList();
        return CallToolResult(content: [TextContent(text: jsonEncode(data))]);
      },
    );

    server.registerTool(
      'hiddify_select_node',
      description: 'Select a node within a proxy group.',
      inputSchema: JsonSchema.object(
        properties: {
          'groupTag': JsonSchema.string(description: 'Group tag'),
          'outboundTag': JsonSchema.string(description: 'Node tag'),
        },
        required: ['groupTag', 'outboundTag'],
      ),
      callback: (args, extra) async {
        await ref
            .read(proxiesOverviewNotifierProvider.notifier)
            .changeProxy(
              args['groupTag'] as String,
              args['outboundTag'] as String,
            );
        return CallToolResult(content: [TextContent(text: 'node selected')]);
      },
    );

    server.registerTool(
      'hiddify_service_mode',
      description:
          'Set the service mode. mode is one of: proxy, system-proxy, vpn.',
      inputSchema: JsonSchema.object(
        properties: {
          'mode': JsonSchema.string(description: 'proxy | system-proxy | vpn'),
        },
        required: ['mode'],
      ),
      callback: (args, extra) async {
        final mode = _parseServiceMode(args['mode'] as String);
        if (mode == null) {
          return CallToolResult(
            isError: true,
            content: const [
              TextContent(
                text: 'unknown service mode (use proxy, system-proxy or vpn)',
              ),
            ],
          );
        }
        ref.read(ConfigOptions.serviceMode.notifier).update(mode);
        return CallToolResult(content: [TextContent(text: 'service mode set')]);
      },
    );

    server.registerTool(
      'hiddify_url_test',
      description: 'Run a URL/speed test. Omit tag to test all.',
      inputSchema: JsonSchema.object(
        properties: {
          'tag': JsonSchema.string(
            description: 'Optional node tag; omit to test all',
          ),
        },
      ),
      callback: (args, extra) async {
        final tag = args['tag'] as String?;
        final repo = ref.read(proxyRepositoryProvider);
        await repo.urlTest(tag ?? '').run();
        return CallToolResult(content: [TextContent(text: 'url test started')]);
      },
    );
  }

  ServiceMode? _parseServiceMode(String mode) {
    for (final m in ServiceMode.values) {
      if (m.key == mode) return m;
    }
    return null;
  }
}
