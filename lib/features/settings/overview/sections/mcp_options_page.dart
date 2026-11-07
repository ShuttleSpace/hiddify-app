import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:uuid/uuid.dart';

class McpOptionsPage extends HookConsumerWidget {
  const McpOptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(Preferences.enableMcpServer);
    final port = ref.watch(Preferences.mcpPort);
    final token = ref.watch(Preferences.mcpToken);

    return Scaffold(
      appBar: AppBar(title: const Text('MCP 控制服务')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile.adaptive(
            title: const Text('启用 MCP 服务'),
            subtitle: const Text(
              '允许本机 agent 通过 MCP 控制 Hiddify（仅监听回环地址，需 Bearer Token）',
            ),
            value: enabled,
            onChanged: ref.read(Preferences.enableMcpServer.notifier).update,
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: port.toString(),
            decoration: const InputDecoration(
              labelText: '监听端口',
              hintText: 'http://127.0.0.1:<port>/mcp',
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final p = int.tryParse(value);
              if (p != null && p > 0 && p <= 65535) {
                ref.read(Preferences.mcpPort.notifier).update(p);
              }
            },
          ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('访问令牌 (Bearer Token)'),
            subtitle: Text(token.isEmpty ? '（启用后将自动生成）' : token),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (token.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: '复制',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: token));
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '重新生成',
                  onPressed: () =>
                      ref.read(Preferences.mcpToken.notifier).update(const Uuid().v4()),
                ),
              ],
            ),
          ),
          const Divider(),
          const Text(
            'Agent 接入示例（MCP over Streamable HTTP）：',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              '{\n'
              '  "mcpServers": {\n'
              '    "hiddify": {\n'
              '      "url": "http://127.0.0.1:$port/mcp",\n'
              '      "headers": { "Authorization": "Bearer ${token.isEmpty ? "<token>" : token}" }\n'
              '    }\n'
              '  }\n'
              '}',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '修改端口或启用状态后需重启应用生效。',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
