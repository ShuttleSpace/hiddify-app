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
      ref.read(inAppNotificationControllerProvider).showInfoToast('Current node is blacklisted');
    }
  });
});
