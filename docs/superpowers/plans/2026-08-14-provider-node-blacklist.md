# Provider Node Blacklist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add provider-aware node blacklist CRUD, matching, filtering, import/export, and current-node protection.

**Architecture:** A local JSON document stores global rules and per-provider rules. A pure matching engine filters `OutboundInfo`. A Riverpod `StateNotifier` owns the loaded document and exposes CRUD/import/export operations. Existing proxy pages consume the same engine.

**Tech Stack:** Flutter, Dart, Riverpod, `dart:io`, `dart:convert`, existing `FilePicker`, existing translation generation via slang.

## Global Constraints

- Node blacklist data lives at `<workingDir>/node_blacklist.json`.
- Do not modify sing-box subscription configuration.
- Provider policies are `useGlobal`, `customOnly`, and `globalPlusCustom`.
- Rule match modes are `any` and `all`.
- Import/export supports JSON file, clipboard JSON, plain text, and `hiddify://settings/node-blacklist?data=...`.
- Current selected node is not force-disconnected; the app prompts the user.
- Generated translation files are regenerated with `dart run slang`.
- Run `dart analyze lib` after each task; there must be no `error`.

---

### Task 1: Node Blacklist Models

**Files:**
- Create: `lib/features/proxy/model/node_blacklist.dart`
- Test: `test/features/proxy/model/node_blacklist_test.dart`

**Interfaces:**
- Produces:
  - `enum NodeBlacklistField { countryCode, region, city, nodeName, ipCidr, asn, organization }`
  - `enum NodeBlacklistOperator { equals, contains, startsWith, cidrMatch }`
  - `enum NodeBlacklistMatchMode { any, all }`
  - `enum NodeBlacklistPolicy { useGlobal, customOnly, globalPlusCustom }`
  - `class NodeBlacklistCondition`
  - `class NodeBlacklistRule`
  - `class ProviderNodeBlacklist`
  - `class NodeBlacklistDocument`

- [ ] **Step 1: Write model test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/proxy/model/node_blacklist_test.dart`
Expected: compile failure because `node_blacklist.dart` does not exist.

- [ ] **Step 3: Implement models**

Create `lib/features/proxy/model/node_blacklist.dart` with plain immutable classes and manual `toJson`/`fromJson`:

```dart
enum NodeBlacklistField { countryCode, region, city, nodeName, ipCidr, asn, organization }

enum NodeBlacklistOperator { equals, contains, startsWith, cidrMatch }

enum NodeBlacklistMatchMode { any, all }

enum NodeBlacklistPolicy { useGlobal, customOnly, globalPlusCustom }

class NodeBlacklistCondition {
  const NodeBlacklistCondition({
    required this.field,
    required this.operator,
    required this.value,
  });

  final NodeBlacklistField field;
  final NodeBlacklistOperator operator;
  final String value;

  Map<String, dynamic> toJson() => {
    'field': field.name,
    'operator': operator.name,
    'value': value,
  };

  static NodeBlacklistCondition fromJson(Map<String, dynamic> json) => NodeBlacklistCondition(
    field: NodeBlacklistField.values.byName(json['field'] as String),
    operator: NodeBlacklistOperator.values.byName(json['operator'] as String),
    value: json['value'] as String,
  );

  NodeBlacklistCondition copyWith({String? value}) => NodeBlacklistCondition(
    field: field,
    operator: operator,
    value: value ?? this.value,
  );
}

class NodeBlacklistRule {
  const NodeBlacklistRule({
    required this.enabled,
    required this.name,
    required this.matchMode,
    required this.conditions,
  });

  final bool enabled;
  final String name;
  final NodeBlacklistMatchMode matchMode;
  final List<NodeBlacklistCondition> conditions;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'name': name,
    'matchMode': matchMode.name,
    'conditions': conditions.map((e) => e.toJson()).toList(),
  };

  static NodeBlacklistRule fromJson(Map<String, dynamic> json) => NodeBlacklistRule(
    enabled: json['enabled'] as bool? ?? true,
    name: json['name'] as String? ?? '',
    matchMode: NodeBlacklistMatchMode.values.byName(json['matchMode'] as String? ?? 'any'),
    conditions: ((json['conditions'] as List<dynamic>?) ?? [])
        .map((e) => NodeBlacklistCondition.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class ProviderNodeBlacklist {
  const ProviderNodeBlacklist({
    required this.policy,
    required this.rules,
  });

  final NodeBlacklistPolicy policy;
  final List<NodeBlacklistRule> rules;

  Map<String, dynamic> toJson() => {
    'policy': policy.name,
    'rules': rules.map((e) => e.toJson()).toList(),
  };

  static ProviderNodeBlacklist fromJson(Map<String, dynamic> json) => ProviderNodeBlacklist(
    policy: NodeBlacklistPolicy.values.byName(json['policy'] as String? ?? 'useGlobal'),
    rules: ((json['rules'] as List<dynamic>?) ?? [])
        .map((e) => NodeBlacklistRule.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class NodeBlacklistDocument {
  const NodeBlacklistDocument({
    required this.version,
    required this.globalRules,
    required this.providers,
  });

  final int version;
  final List<NodeBlacklistRule> globalRules;
  final Map<String, ProviderNodeBlacklist> providers;

  Map<String, dynamic> toJson() => {
    'version': version,
    'global': {'rules': globalRules.map((e) => e.toJson()).toList()},
    'providers': providers.map((key, value) => MapEntry(key, value.toJson())),
  };

  static NodeBlacklistDocument fromJson(Map<String, dynamic> json) => NodeBlacklistDocument(
    version: json['version'] as int? ?? 1,
    globalRules: ((json['global'] as Map<String, dynamic>?)?['rules'] as List<dynamic>? ?? [])
        .map((e) => NodeBlacklistRule.fromJson(e as Map<String, dynamic>))
        .toList(),
    providers: ((json['providers'] as Map<String, dynamic>?) ?? {})
        .map((key, value) => MapEntry(key, ProviderNodeBlacklist.fromJson(value as Map<String, dynamic>))),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/proxy/model/node_blacklist_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/proxy/model/node_blacklist.dart test/features/proxy/model/node_blacklist_test.dart
git commit -m "feat: add node blacklist models"
```

---

### Task 2: Blacklist Matching Engine

**Files:**
- Create: `lib/features/proxy/data/node_blacklist_engine.dart`
- Test: `test/features/proxy/data/node_blacklist_engine_test.dart`

**Interfaces:**
- Consumes: `NodeBlacklistDocument`, `NodeBlacklistRule`, `NodeBlacklistPolicy`, `OutboundInfo`.
- Produces:
  - `List<NodeBlacklistRule> effectiveRules(NodeBlacklistDocument document, String? profileId)`
  - `bool isNodeBlacklisted(OutboundInfo node, List<NodeBlacklistRule> rules)`
  - `List<NodeBlacklistRule> matchingRules(OutboundInfo node, List<NodeBlacklistRule> rules)`

- [ ] **Step 1: Write engine tests**

```dart
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
      NodeBlacklistCondition(field: NodeBlacklistField.countryCode, operator: NodeBlacklistOperator.equals, value: 'HK'),
    ],
  );

  final nameRule = NodeBlacklistRule(
    enabled: true,
    name: 'Claude',
    matchMode: NodeBlacklistMatchMode.all,
    conditions: const [
      NodeBlacklistCondition(field: NodeBlacklistField.countryCode, operator: NodeBlacklistOperator.equals, value: 'HK'),
      NodeBlacklistCondition(field: NodeBlacklistField.nodeName, operator: NodeBlacklistOperator.contains, value: 'Claude'),
    ],
  );

  test('country and name matching work', () {
    final node = OutboundInfo(
      tag: 'Claude-HK',
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
        'p1': ProviderNodeBlacklist(policy: NodeBlacklistPolicy.customOnly, rules: []),
        'p2': ProviderNodeBlacklist(policy: NodeBlacklistPolicy.globalPlusCustom, rules: []),
      },
    );

    expect(effectiveRules(doc, 'p1'), isEmpty);
    expect(effectiveRules(doc, 'p2'), [hkRule]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/proxy/data/node_blacklist_engine_test.dart`
Expected: compile failure because engine does not exist.

- [ ] **Step 3: Implement engine**

```dart
import 'package:hiddify/features/proxy/model/node_blacklist.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

List<NodeBlacklistRule> effectiveRules(NodeBlacklistDocument document, String? profileId) {
  final provider = profileId == null ? null : document.providers[profileId];
  final policy = provider?.policy ?? NodeBlacklistPolicy.useGlobal;

  return switch (policy) {
    NodeBlacklistPolicy.useGlobal => document.globalRules,
    NodeBlacklistPolicy.customOnly => provider?.rules ?? const [],
    NodeBlacklistPolicy.globalPlusCustom => [...document.globalRules, ...?provider?.rules],
  }.where((rule) => rule.enabled).toList();
}

bool isNodeBlacklisted(OutboundInfo node, List<NodeBlacklistRule> rules) {
  return matchingRules(node, rules).isNotEmpty;
}

List<NodeBlacklistRule> matchingRules(OutboundInfo node, List<NodeBlacklistRule> rules) {
  return rules.where((rule) => _ruleMatches(node, rule)).toList();
}

bool _ruleMatches(OutboundInfo node, NodeBlacklistRule rule) {
  if (rule.conditions.isEmpty) return false;
  final matches = rule.conditions.map((condition) => _conditionMatches(node, condition));
  return switch (rule.matchMode) {
    NodeBlacklistMatchMode.any => matches.any((value) => value),
    NodeBlacklistMatchMode.all => matches.every((value) => value),
  };
}

bool _conditionMatches(OutboundInfo node, NodeBlacklistCondition condition) {
  final raw = switch (condition.field) {
    NodeBlacklistField.countryCode => node.ipinfo.countryCode,
    NodeBlacklistField.region => node.ipinfo.region,
    NodeBlacklistField.city => node.ipinfo.city,
    NodeBlacklistField.nodeName => node.tagDisplay,
    NodeBlacklistField.ipCidr => node.ipinfo.ip,
    NodeBlacklistField.asn => node.ipinfo.asn.toString(),
    NodeBlacklistField.organization => node.ipinfo.org,
  };
  final value = raw.trim().toLowerCase();
  final target = condition.value.trim().toLowerCase();

  if (condition.operator == NodeBlacklistOperator.cidrMatch) {
    final nodeIp = node.ipinfo.ip;
    return nodeIp.isNotEmpty && _ipMatchesCidr(nodeIp, condition.value.trim());
  }

  return switch (condition.operator) {
    NodeBlacklistOperator.equals => value == target,
    NodeBlacklistOperator.contains => value.contains(target),
    NodeBlacklistOperator.startsWith => value.startsWith(target),
    NodeBlacklistOperator.cidrMatch => false,
  };
}

bool _ipMatchesCidr(String ip, String cidr) {
  if (cidr.contains('/')) {
    final parts = cidr.split('/');
    final prefix = int.tryParse(parts[1]);
    if (prefix == null) return false;
    return _toIpv4Int(ip) != null && _toIpv4Int(parts[0]) != null &&
        (_toIpv4Int(ip)! & _mask(prefix)) == (_toIpv4Int(parts[0])! & _mask(prefix));
  }
  return ip == cidr;
}

int? _toIpv4Int(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return null;
  var result = 0;
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null || number < 0 || number > 255) return null;
    result = (result << 8) | number;
  }
  return result;
}

int _mask(int prefix) => prefix <= 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
```

- [ ] **Step 4: Run tests to verify pass**

Run: `flutter test test/features/proxy/data/node_blacklist_engine_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/proxy/data/node_blacklist_engine.dart test/features/proxy/data/node_blacklist_engine_test.dart
git commit -m "feat: add node blacklist matching engine"
```

---

### Task 3: Blacklist Repository

**Files:**
- Create: `lib/features/proxy/data/node_blacklist_repository.dart`
- Test: `test/features/proxy/data/node_blacklist_repository_test.dart`

**Interfaces:**
- Consumes: `NodeBlacklistDocument`, `dart:io`.
- Produces:
  - `class NodeBlacklistRepository`
  - `NodeBlacklistDocument load()`
  - `Future<void> save(NodeBlacklistDocument document)`

- [ ] **Step 1: Write repository test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/data/node_blacklist_repository.dart';
import 'package:hiddify/features/proxy/model/node_blacklist.dart';

void main() {
  test('repository saves and loads a document', () async {
    final dir = await Directory.systemTemp.createTemp('node-blacklist-test');
    final file = File('${dir.path}/node_blacklist.json');
    final repo = NodeBlacklistRepository(file);
    final doc = NodeBlacklistDocument(version: 1, globalRules: [], providers: const {});

    await repo.save(doc);
    expect(repo.load().version, 1);

    await dir.delete(recursive: true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/proxy/data/node_blacklist_repository_test.dart`
Expected: compile failure because repository does not exist.

- [ ] **Step 3: Implement repository**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:hiddify/features/proxy/model/node_blacklist.dart';

class NodeBlacklistRepository {
  const NodeBlacklistRepository(this.file);

  final File file;

  NodeBlacklistDocument load() {
    if (!file.existsSync()) {
      return const NodeBlacklistDocument(version: 1, globalRules: [], providers: {});
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return NodeBlacklistDocument.fromJson(json);
  }

  Future<void> save(NodeBlacklistDocument document) async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(document.toJson()), flush: true);
  }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/proxy/data/node_blacklist_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/proxy/data/node_blacklist_repository.dart test/features/proxy/data/node_blacklist_repository_test.dart
git commit -m "feat: add node blacklist repository"
```

---

### Task 4: Controller and Providers

**Files:**
- Create: `lib/features/proxy/notifier/node_blacklist_controller.dart`
- Modify: `lib/features/app/widget/app.dart`

**Interfaces:**
- Produces:
  - `final nodeBlacklistRepositoryProvider = Provider<NodeBlacklistRepository>`
  - `final nodeBlacklistControllerProvider = StateNotifierProvider<NodeBlacklistController, NodeBlacklistDocument>`
  - Controller methods: `updateGlobalRule`, `deleteGlobalRule`, `setProviderPolicy`, `updateProviderRule`, `deleteProviderRule`, `importDocument`, `exportDocument`

- [ ] **Step 1: Create controller**

```dart
import 'dart:io';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/proxy/data/node_blacklist_engine.dart';
import 'package:hiddify/features/proxy/data/node_blacklist_repository.dart';
import 'package:hiddify/features/proxy/model/node_blacklist.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final nodeBlacklistRepositoryProvider = Provider<NodeBlacklistRepository>((ref) {
  final dirs = ref.watch(appDirectoriesProvider).requireValue;
  return NodeBlacklistRepository(File('${dirs.baseDir.path}/node_blacklist.json'));
});

class NodeBlacklistController extends StateNotifier<NodeBlacklistDocument> {
  NodeBlacklistController(this._repo) : super(_repo.load());

  final NodeBlacklistRepository _repo;

  Future<void> _save(NodeBlacklistDocument document) async {
    state = document;
    await _repo.save(document);
  }

  Future<void> upsertGlobalRule(NodeBlacklistRule rule, {int? index}) async {
    final rules = [...state.globalRules];
    if (index == null) {
      rules.add(rule);
    } else if (index >= 0 && index < rules.length) {
      rules[index] = rule;
    } else {
      rules.add(rule);
    }
    await _save(NodeBlacklistDocument(version: state.version, globalRules: rules, providers: state.providers));
  }

  Future<void> deleteGlobalRule(int index) async {
    final rules = [...state.globalRules]..removeAt(index);
    await _save(NodeBlacklistDocument(version: state.version, globalRules: rules, providers: state.providers));
  }

  Future<void> setProviderPolicy(String profileId, NodeBlacklistPolicy policy) async {
    final providers = {...state.providers};
    final current = providers[profileId] ?? const ProviderNodeBlacklist(policy: NodeBlacklistPolicy.useGlobal, rules: []);
    providers[profileId] = ProviderNodeBlacklist(policy: policy, rules: current.rules);
    await _save(NodeBlacklistDocument(version: state.version, globalRules: state.globalRules, providers: providers));
  }

  Future<void> upsertProviderRule(String profileId, NodeBlacklistRule rule, {int? index}) async {
    final providers = {...state.providers};
    final current = providers[profileId] ?? const ProviderNodeBlacklist(policy: NodeBlacklistPolicy.useGlobal, rules: []);
    final rules = [...current.rules];
    if (index == null) {
      rules.add(rule);
    } else if (index >= 0 && index < rules.length) {
      rules[index] = rule;
    } else {
      rules.add(rule);
    }
    providers[profileId] = ProviderNodeBlacklist(policy: current.policy, rules: rules);
    await _save(NodeBlacklistDocument(version: state.version, globalRules: state.globalRules, providers: providers));
  }

  Future<void> deleteProviderRule(String profileId, int index) async {
    final providers = {...state.providers};
    final current = providers[profileId];
    if (current == null || index < 0 || index >= current.rules.length) return;
    final rules = [...current.rules]..removeAt(index);
    providers[profileId] = ProviderNodeBlacklist(policy: current.policy, rules: rules);
    await _save(NodeBlacklistDocument(version: state.version, globalRules: state.globalRules, providers: providers));
  }

  Future<void> importDocument(NodeBlacklistDocument document) => _save(document);

  NodeBlacklistDocument exportDocument() => state;
}

final nodeBlacklistControllerProvider = StateNotifierProvider<NodeBlacklistController, NodeBlacklistDocument>(
  (ref) => NodeBlacklistController(ref.watch(nodeBlacklistRepositoryProvider)),
);
```

- [ ] **Step 2: Import and keep alive in app**

In `lib/features/app/widget/app.dart`, add:

```dart
import 'package:hiddify/features/proxy/notifier/node_blacklist_controller.dart';
```

Inside `App.build`, before the existing provider listeners:

```dart
if (PlatformUtils.isDesktop) ref.listen(nodeBlacklistControllerProvider, (_, _) {});
```

- [ ] **Step 3: Analyze**

Run: `dart analyze lib/features/proxy/notifier/node_blacklist_controller.dart lib/features/app/widget/app.dart`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/proxy/notifier/node_blacklist_controller.dart lib/features/app/widget/app.dart
git commit -m "feat: add node blacklist controller"
```

---

### Task 5: Filter Node List and Add Management Entry

**Files:**
- Modify: `lib/features/proxy/overview/proxies_overview_notifier.dart`
- Modify: `lib/features/proxy/overview/proxies_overview_page.dart`

**Interfaces:**
- Consumes: `nodeBlacklistControllerProvider`, `effectiveRules`, `isNodeBlacklisted`.
- Produces: filtered `OutboundGroup` stream and a “filtered count” exposed to the page.

- [ ] **Step 1: Add filter helper to notifier**

In `ProxiesOverviewNotifier`, import:

```dart
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/data/node_blacklist_engine.dart';
import 'package:hiddify/features/proxy/notifier/node_blacklist_controller.dart';
```

Change the stream mapping before `_sortOutbounds`:

```dart
.map((event) => event.getOrElse((err) {
    loggy.warning("error receiving proxies", err);
    throw err;
  }))
.map((proxies) {
    if (proxies == null) return proxies;
    final profileId = ref.read(activeProfileProvider).valueOrNull?.id;
    final doc = ref.read(nodeBlacklistControllerProvider);
    final rules = effectiveRules(doc, profileId);
    proxies.items = proxies.items.where((node) => !isNodeBlacklisted(node, rules)).toList();
    return proxies;
  })
.asyncMap((proxies) async => await _sortOutbounds(proxies, sortBy));
```

The filtered count can be derived by comparing `OutboundGroup.items.length` before and after filtering.

- [ ] **Step 2: Add filtered count UI**

In `ProxiesOverviewPage.build`, add an `AppBar` action:

```dart
IconButton(
  tooltip: 'Node blacklist',
  onPressed: () => context.goNamed('nodeBlacklist'),
  icon: const Icon(Icons.block_rounded),
),
```

Add the same top action to the page body if preferred. The page already has a node list, so the action is sufficient for the first integration pass.

- [ ] **Step 3: Analyze**

Run: `dart analyze lib/features/proxy/overview/proxies_overview_notifier.dart lib/features/proxy/overview/proxies_overview_page.dart`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/proxy/overview/proxies_overview_notifier.dart lib/features/proxy/overview/proxies_overview_page.dart
git commit -m "feat: filter provider nodes through blacklist"
```

---

### Task 6: Provider Details Blacklist Section

**Files:**
- Modify: `lib/features/profile/details/profile_details_page.dart`
- Modify: `lib/features/profile/model/profile_entity.dart` only if a persistent profile id is not already available through `data.profile.id`; no model change is required.

**Interfaces:**
- Consumes: `nodeBlacklistControllerProvider`, `NodeBlacklistPolicy`, `NodeBlacklistRule`.

- [ ] **Step 1: Add provider policy selector**

In `ProfileDetailsPage`, after the existing profile URL/home page section, add:

```dart
if (data.profile case RemoteProfileEntity(:final id)) ...[
  const Divider(indent: 16, endIndent: 16),
  ListTile(
    title: Text('Node blacklist'),
    subtitle: Text('Manage provider-specific node filtering'),
    trailing: const Icon(Icons.block_rounded),
    onTap: () => context.goNamed('providerNodeBlacklist', pathParameters: {'id': id}),
  ),
],
```

- [ ] **Step 2: Analyze**

Run: `dart analyze lib/features/profile/details/profile_details_page.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/profile/details/profile_details_page.dart
git commit -m "feat: add provider node blacklist entry"
```

---

### Task 7: Global and Provider Blacklist Management Pages

**Files:**
- Create: `lib/features/proxy/overview/node_blacklist_management_page.dart`
- Modify: `lib/core/router/go_router/routing_config_notifier.dart`

**Interfaces:**
- Produces: `NodeBlacklistManagementPage(profileId: String?)`.

- [ ] **Step 1: Create management page**

The page takes `profileId`. It displays:

- provider policy dropdown when `profileId != null`
- rule list
- add/edit/delete buttons
- import/export actions

Minimal implementation:

```dart
class NodeBlacklistManagementPage extends ConsumerWidget {
  const NodeBlacklistManagementPage({super.key, this.profileId});

  final String? profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(nodeBlacklistControllerProvider);
    final provider = profileId == null ? null : document.providers[profileId];
    final rules = profileId == null ? document.globalRules : provider?.rules ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Node Blacklist')),
      body: ListView(
        children: [
          if (profileId != null)
            DropdownButton<NodeBlacklistPolicy>(
              value: provider?.policy ?? NodeBlacklistPolicy.useGlobal,
              items: NodeBlacklistPolicy.values
                  .map((policy) => DropdownMenuItem(value: policy, child: Text(policy.name)))
                  .toList(),
              onChanged: (policy) {
                if (policy != null) {
                  ref.read(nodeBlacklistControllerProvider.notifier).setProviderPolicy(profileId!, policy);
                }
              },
            ),
          for (var i = 0; i < rules.length; i++)
            ListTile(
              title: Text(rules[i].name),
              subtitle: Text(rules[i].matchMode.name),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  if (profileId == null) {
                    ref.read(nodeBlacklistControllerProvider.notifier).deleteGlobalRule(i);
                  } else {
                    ref.read(nodeBlacklistControllerProvider.notifier).deleteProviderRule(profileId!, i);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add routes**

In `routing_config_notifier.dart`, inside the settings `StatefulShellBranch` `routes` list, before the existing settings routes, add:

```dart
GoRoute(
  name: 'nodeBlacklist',
  path: 'node-blacklist',
  builder: (_, _) => const NodeBlacklistManagementPage(),
),
GoRoute(
  name: 'providerNodeBlacklist',
  path: 'provider-node-blacklist/:id',
  builder: (_, state) => NodeBlacklistManagementPage(profileId: state.pathParameters['id']),
),
```

Place these under the existing settings or home branch according to the app’s route structure.

- [ ] **Step 3: Analyze**

Run: `dart analyze lib/features/proxy/overview/node_blacklist_management_page.dart lib/core/router/go_router/routing_config_notifier.dart`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/proxy/overview/node_blacklist_management_page.dart lib/core/router/go_router/routing_config_notifier.dart
git commit -m "feat: add node blacklist management pages"
```

---

### Task 8: Import and Export

**Files:**
- Create: `lib/features/proxy/data/node_blacklist_io.dart`
- Modify: `lib/features/proxy/overview/node_blacklist_management_page.dart`

**Interfaces:**
- Produces:
  - `String exportToJson(NodeBlacklistDocument document)`
  - `NodeBlacklistDocument importFromJson(String input)`
  - `String exportDeepLink(NodeBlacklistDocument document)`
  - `NodeBlacklistDocument importFromDeepLink(String deepLink)`
  - `List<String> plainTextLines(String input)`

- [ ] **Step 1: Implement IO helpers**

```dart
import 'package:flutter/services.dart';

import 'dart:convert';

import 'package:hiddify/features/proxy/model/node_blacklist.dart';

String exportToJson(NodeBlacklistDocument document) {
  return const JsonEncoder.withIndent('  ').convert(document.toJson());
}

NodeBlacklistDocument importFromJson(String input) {
  return NodeBlacklistDocument.fromJson(jsonDecode(input) as Map<String, dynamic>);
}

String exportDeepLink(NodeBlacklistDocument document) {
  final data = base64Encode(utf8.encode(exportToJson(document)));
  return 'hiddify://settings/node-blacklist?data=$data';
}

NodeBlacklistDocument importFromDeepLink(String deepLink) {
  final data = Uri.parse(deepLink).queryParameters['data'];
  if (data == null) throw const FormatException('Missing data');
  return importFromJson(utf8.decode(base64Decode(data)));
}

List<String> plainTextLines(String input) {
  return input
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}
```

- [ ] **Step 2: Add import/export buttons**

In `NodeBlacklistManagementPage`, add actions:

```dart
IconButton(
  tooltip: 'Copy JSON',
  icon: const Icon(Icons.copy_rounded),
  onPressed: () => Clipboard.setData(ClipboardData(text: exportToJson(document))),
),
IconButton(
  tooltip: 'Paste JSON',
  icon: const Icon(Icons.content_paste_rounded),
  onPressed: () async {
    final text = await Clipboard.getData(Clipboard.kTextPlain);
    if (text?.text == null) return;
    ref.read(nodeBlacklistControllerProvider.notifier).importDocument(importFromJson(text!.text!));
  },
),
```

- [ ] **Step 3: Analyze**

Run: `dart analyze lib/features/proxy/data/node_blacklist_io.dart lib/features/proxy/overview/node_blacklist_management_page.dart`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/proxy/data/node_blacklist_io.dart lib/features/proxy/overview/node_blacklist_management_page.dart
git commit -m "feat: add node blacklist import export"
```

---

### Task 9: Current Node Protection

**Files:**
- Create: `lib/features/proxy/notifier/active_proxy_blacklist_guard.dart`
- Modify: `lib/features/app/widget/app.dart`

**Interfaces:**
- Produces:
  - `final activeProxyBlacklistGuardProvider = Provider<void>`

- [ ] **Step 1: Create guard**

```dart
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/data/node_blacklist_engine.dart';
import 'package:hiddify/features/proxy/notifier/node_blacklist_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final activeProxyBlacklistGuardProvider = Provider<void>((ref) {
  ref.listen(activeProxyNotifierProvider, (_, next) {
    final node = next.valueOrNull;
    if (node == null) return;
    final doc = ref.read(nodeBlacklistControllerProvider);
    final rules = effectiveRules(doc, node.tag);
    if (isNodeBlacklisted(node, rules)) {
      // Show a non-blocking toast; do not disconnect.
      ref.read(inAppNotificationControllerProvider).showInfoToast('Current node is blacklisted');
    }
  });
});
```

- [ ] **Step 2: Keep guard alive**

In `App.build`, add:

```dart
ref.listen(activeProxyBlacklistGuardProvider, (_, _) {});
```

- [ ] **Step 3: Analyze**

Run: `dart analyze lib/features/proxy/notifier/active_proxy_blacklist_guard.dart lib/features/app/widget/app.dart`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/proxy/notifier/active_proxy_blacklist_guard.dart lib/features/app/widget/app.dart
git commit -m "feat: guard currently selected blacklisted node"
```

---

### Task 10: Translations and Final Verification

**Files:**
- Modify: `assets/translations/en.i18n.json`
- Modify: `assets/translations/zh-CN.i18n.json`
- Modify: generated files via `dart run slang`

- [ ] **Step 1: Add translation keys**

Under `pages.settings` add:

```json
"nodeBlacklist": {
  "title": "Node blacklist",
  "global": "Global rules",
  "provider": "Provider rules",
  "filteredCount": "Filtered nodes",
  "showFiltered": "Show filtered nodes",
  "importJson": "Import JSON",
  "exportJson": "Export JSON",
  "importText": "Import plain text",
  "currentNodeBlocked": "Current node is blacklisted"
}
```

Chinese values can be provided alongside English; exact values are implementation-owned and not part of this plan.

- [ ] **Step 2: Regenerate translations**

Run:

```bash
/Users/ahs/.puro/envs/default/flutter/bin/cache/dart-sdk/bin/dart --packages=.dart_tool/package_config.json /Users/ahs/.puro/shared/pub_cache/hosted/pub.flutter-io.cn/slang-4.19.0/bin/slang.dart
```

- [ ] **Step 3: Analyze and test**

Run:

```bash
dart analyze lib
flutter test test/features/proxy/model/node_blacklist_test.dart test/features/proxy/data/node_blacklist_engine_test.dart test/features/proxy/data/node_blacklist_repository_test.dart
```

Expected: no errors and tests pass.

- [ ] **Step 4: Build bundle**

Run:

```bash
flutter build bundle --debug --no-pub
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add assets/translations/en.i18n.json assets/translations/zh-CN.i18n.json lib/gen
git commit -m "feat: add node blacklist translations"
```

---
