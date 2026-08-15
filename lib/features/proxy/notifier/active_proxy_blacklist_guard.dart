import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/data/node_blacklist_engine.dart';
import 'package:hiddify/features/proxy/notifier/node_blacklist_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final activeProxyBlacklistGuardProvider = Provider<void>((ref) {
  ref.listen(activeProxyNotifierProvider, (_, next) {
    final node = next.valueOrNull;
    if (node == null) return;
    final doc = ref.read(nodeBlacklistControllerProvider);
    final profileId = ref.read(activeProfileProvider).valueOrNull?.id;
    final rules = effectiveRules(doc, profileId);
    if (isNodeBlacklisted(node, rules)) {
      final t = ref.read(translationsProvider).valueOrNull;
      if (t == null) return;
      ref
          .read(inAppNotificationControllerProvider)
          .showInfoToast(t.pages.proxies.nodeBlacklist.nodeDisabled(name: node.tagDisplay));
    }
  });
});
