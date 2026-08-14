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
