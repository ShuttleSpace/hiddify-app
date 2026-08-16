import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/appearance_options.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AppearancePage extends HookConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final colorSource = ref.watch(AppearanceOptions.colorSource);
    final seedColor = Color(ref.watch(AppearanceOptions.seedColorValue));

    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.appearance.title)),
      body: ListView(
        children: [
          const ThemeModePrefTile(),
          ListTile(
            leading: const Icon(Icons.format_size_rounded),
            title: Text(t.pages.settings.appearance.textSize),
            subtitle: Text(_presentTextScale(ref.watch(AppearanceOptions.textScaleMode), t)),
            onTap: () async {
              final selected = await ref
                  .read(dialogNotifierProvider.notifier)
                  .showSettingPicker<AppTextScaleMode>(
                    title: t.pages.settings.appearance.textSize,
                    selected: ref.watch(AppearanceOptions.textScaleMode),
                    onReset: () => ref.read(AppearanceOptions.textScaleMode.notifier).update(AppTextScaleMode.system),
                    options: AppTextScaleMode.values,
                    getTitle: (value) => _presentTextScale(value, t),
                  );
              if (selected != null) {
                await ref.read(AppearanceOptions.textScaleMode.notifier).update(selected);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_rounded),
            title: Text(t.pages.settings.appearance.themeColor),
            subtitle: Text(_presentColorSource(colorSource, t)),
            onTap: () async {
              final selected = await ref
                  .read(dialogNotifierProvider.notifier)
                  .showSettingPicker<AppColorSource>(
                    title: t.pages.settings.appearance.themeColor,
                    selected: colorSource,
                    onReset: () => ref.read(AppearanceOptions.colorSource.notifier).update(AppColorSource.brand),
                    options: AppColorSource.values,
                    getTitle: (value) => _presentColorSource(value, t),
                  );
              if (selected != null) {
                await ref.read(AppearanceOptions.colorSource.notifier).update(selected);
              }
            },
          ),
          if (colorSource == AppColorSource.seed) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(t.pages.settings.appearance.presetColors, style: Theme.of(context).textTheme.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final color in _presetColors)
                    _ColorSwatch(
                      color: color,
                      selected: color.toARGB32() == seedColor.toARGB32(),
                      onTap: () {
                        ref.read(AppearanceOptions.seedColorValue.notifier).update(color.toARGB32());
                        ref.read(AppearanceOptions.colorSource.notifier).update(AppColorSource.seed);
                      },
                    ),
                ],
              ),
            ),
            const Gap(8),
          ],
        ],
      ),
    );
  }

  String _presentTextScale(AppTextScaleMode value, Translations t) => switch (value) {
    AppTextScaleMode.system => t.pages.settings.appearance.textSizes.system,
    AppTextScaleMode.small => t.pages.settings.appearance.textSizes.small,
    AppTextScaleMode.standard => t.pages.settings.appearance.textSizes.standard,
    AppTextScaleMode.large => t.pages.settings.appearance.textSizes.large,
    AppTextScaleMode.extraLarge => t.pages.settings.appearance.textSizes.extraLarge,
  };

  String _presentColorSource(AppColorSource value, Translations t) => switch (value) {
    AppColorSource.brand => t.pages.settings.appearance.themeColors.brand,
    AppColorSource.dynamicColor => t.pages.settings.appearance.themeColors.dynamicColor,
    AppColorSource.seed => t.pages.settings.appearance.themeColors.seed,
  };

  static const _presetColors = <Color>[
    Color(0xFF293CA0),
    Color(0xFF00695C),
    Color(0xFFB23A48),
    Color(0xFF7B1FA2),
    Color(0xFF1565C0),
    Color(0xFFF57C00),
  ];
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
        ),
        child: selected ? const Icon(Icons.check_rounded, color: Colors.white) : null,
      ),
    );
  }
}
