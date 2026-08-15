import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ActiveProxyGroupNotifier extends StateNotifier<String?> {
  ActiveProxyGroupNotifier() : super(null);

  void select(String tag) => state = tag;

  void setDefault(List<OutboundGroup> groups) {
    if (state == null || groups.any((group) => group.tag == state)) {
      state = groups.isEmpty ? null : groups.first.tag;
    }
  }
}

final activeProxyGroupNotifierProvider = StateNotifierProvider<ActiveProxyGroupNotifier, String?>(
  (ref) => ActiveProxyGroupNotifier(),
);
