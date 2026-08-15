import 'package:flutter/material.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxyTile extends HookConsumerWidget with PresLogger {
  const ProxyTile(
    this.proxy, {
    super.key,
    required this.selected,
    required this.onTap,
    this.highlight = false,
    this.disabled = false,
  });

  final OutboundInfo proxy;
  final bool selected;
  final GestureTapCallback? onTap;
  final bool highlight;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.45)
            : disabled
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
            : Colors.transparent,
        border: Border.all(color: highlight ? theme.colorScheme.primary : Colors.transparent, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          proxy.tagDisplay,
          overflow: TextOverflow.ellipsis,
          style: PlatformUtils.isWindows ? const TextStyle(fontFamily: FontFamily.emoji) : null,
        ),
        leading: IPCountryFlag(
          countryCode: proxy.ipinfo.countryCode,
          organization: proxy.ipinfo.org,
          size: 40,
          padding: const EdgeInsetsDirectional.only(end: 8),
        ),
        subtitle: Text.rich(
          TextSpan(
            text: proxy.type,
            children: [
              if (proxy.isGroup)
                TextSpan(
                  text: ' (${proxy.groupSelectedTagDisplay.trim()})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              children: [
                if (proxy.urlTestDelay != 0)
                  Text(
                    proxy.urlTestDelay > 65000 ? "×" : proxy.urlTestDelay.toString(),
                    style: TextStyle(color: delayColor(context, proxy.urlTestDelay)),
                  ),
                if (proxy.download > 0) Text("⬩", style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (disabled)
              const Icon(Icons.block_rounded, size: 18, color: Colors.grey)
            else if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: theme.colorScheme.primary),
          ],
        ),

        selected: selected,
        enabled: !disabled,
        selectedTileColor: theme.colorScheme.primaryContainer,
        onTap: disabled ? null : onTap,
        onLongPress: () async => await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: proxy),
        horizontalTitleGap: 4,
      ),
    );
  }

  Color delayColor(BuildContext context, int delay) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return switch (delay) {
        < 800 => Colors.lightGreen,
        < 1500 => Colors.orange,
        _ => Colors.redAccent,
      };
    }
    return switch (delay) {
      < 800 => Colors.green,
      < 1500 => Colors.deepOrangeAccent,
      _ => Colors.red,
    };
  }
}
