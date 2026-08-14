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
  if (condition.operator == NodeBlacklistOperator.cidrMatch) {
    final nodeIp = node.ipinfo.ip;
    return nodeIp.isNotEmpty && _ipMatchesCidr(nodeIp, condition.value.trim());
  }

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
    final ipInt = _toIpv4Int(ip);
    final networkInt = _toIpv4Int(parts[0]);
    if (ipInt == null || networkInt == null) return false;
    final mask = _mask(prefix);
    return (ipInt & mask) == (networkInt & mask);
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

int _mask(int prefix) {
  if (prefix <= 0) return 0;
  if (prefix >= 32) return 0xFFFFFFFF;
  return (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
}
