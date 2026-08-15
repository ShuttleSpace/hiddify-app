import 'dart:io';

import 'package:hiddify/core/directories/directories_provider.dart';
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

  Future<void> setGlobalRuleEnabled(int index, bool enabled) async {
    final rules = [...state.globalRules];
    if (index < 0 || index >= rules.length) return;
    rules[index] = rules[index].copyWith(enabled: enabled);
    await _save(NodeBlacklistDocument(version: state.version, globalRules: rules, providers: state.providers));
  }

  Future<void> setProviderPolicy(String profileId, NodeBlacklistPolicy policy) async {
    final providers = {...state.providers};
    final current =
        providers[profileId] ?? const ProviderNodeBlacklist(policy: NodeBlacklistPolicy.useGlobal, rules: []);
    providers[profileId] = ProviderNodeBlacklist(policy: policy, rules: current.rules);
    await _save(NodeBlacklistDocument(version: state.version, globalRules: state.globalRules, providers: providers));
  }

  Future<void> upsertProviderRule(String profileId, NodeBlacklistRule rule, {int? index}) async {
    final providers = {...state.providers};
    final current =
        providers[profileId] ?? const ProviderNodeBlacklist(policy: NodeBlacklistPolicy.useGlobal, rules: []);
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

  Future<void> setProviderRuleEnabled(String profileId, int index, bool enabled) async {
    final providers = {...state.providers};
    final current = providers[profileId];
    if (current == null || index < 0 || index >= current.rules.length) return;
    final rules = [...current.rules];
    rules[index] = rules[index].copyWith(enabled: enabled);
    providers[profileId] = ProviderNodeBlacklist(policy: current.policy, rules: rules);
    await _save(NodeBlacklistDocument(version: state.version, globalRules: state.globalRules, providers: providers));
  }

  Future<void> importDocument(NodeBlacklistDocument document) => _save(document);

  NodeBlacklistDocument exportDocument() => state;
}

final nodeBlacklistControllerProvider = StateNotifierProvider<NodeBlacklistController, NodeBlacklistDocument>(
  (ref) => NodeBlacklistController(ref.watch(nodeBlacklistRepositoryProvider)),
);
