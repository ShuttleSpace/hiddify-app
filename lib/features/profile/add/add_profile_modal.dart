import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/profile/add/widgets/add_profile_custom_proxy.dart';
import 'package:hiddify/features/profile/add/widgets/free_btns.dart';
import 'package:hiddify/features/profile/add/widgets/widgets.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AddProfileModal extends HookConsumerWidget {
  const AddProfileModal({super.key, this.url});
  // static const warpConsentGiven = "warp_consent_given";
  final String? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(addProfileNotifierProvider).isLoading;
    final currentWidget = ref.watch(addProfilePageNotifierProvider);
    ref.listen(freeSwitchNotifierProvider, (_, _) {});
    ref.listen(addProfileNotifierProvider, (previous, next) {
      if (next case AsyncData(value: final _?)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && context.canPop()) context.pop();
        });
      }
    });

    useMemoized(() async {
      await Future.delayed(const Duration(milliseconds: 200));
      if (url != null && context.mounted) {
        if (isLoading) return;
        ref.read(addProfileNotifierProvider.notifier).addClipboard(url!);
      }
    });
    return SafeArea(
      child: isLoading
          ? const ProfileLoading()
          : switch (currentWidget) {
              AddProfilePages.options => const AddProfileOptions(),
              AddProfilePages.manual => const AddProfileManual(),
            },
    );
  }
}

class AddProfileOptions extends HookConsumerWidget {
  const AddProfileOptions({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // final isLoadingProfile = ref.watch(addProfileNotifierProvider).isLoading;
    final freeSwitch = ref.watch(freeSwitchNotifierProvider);
    final isDesktop = PlatformUtils.isDesktop;
    final gapCount = isDesktop ? AddProfileModalConst.fixBtnsGapCountDesktop : AddProfileModalConst.fixBtnsGapCount;
    final itemCount = isDesktop ? AddProfileModalConst.fixBtnsItemCountDesktop : AddProfileModalConst.fixBtnsItemCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fixBtnsHeight = (constraints.maxWidth - AddProfileModalConst.fixBtnsGap * gapCount) / itemCount;
        final fullHeight = fixBtnsHeight + AddProfileModalConst.navBarHeight + 32;
        final initial = !freeSwitch ? fullHeight : fullHeight + 180;
        var min = !freeSwitch ? fullHeight : fullHeight + 100;
        var max = !freeSwitch ? fullHeight / constraints.maxHeight : 0.85;
        if (isDesktop) {
          min = initial;
          max = initial / constraints.maxHeight;
        }
        return DraggableScrollableSheet(
          initialChildSize: initial / constraints.maxHeight,
          minChildSize: min / constraints.maxHeight,
          maxChildSize: max,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              const Gap(AddProfileModalConst.fixBtnsGap),
              FixBtns(height: fixBtnsHeight),
              if (freeSwitch) Expanded(child: FreeBtns(scrollController: scrollController)) else const Spacer(),
              const NavBar(),
            ],
          ),
        );
      },
    );
  }
}

class AddProfileManual extends HookConsumerWidget {
  const AddProfileManual({super.key});

  String _genSliderText(Translations t, int sliderValue) {
    if (sliderValue == 0) {
      return t.common.auto;
    } else if (sliderValue < 24) {
      return t.common.interval.hour(n: sliderValue);
    }
    final day = t.common.interval.day(n: sliderValue ~/ 24);
    final hour = t.common.interval.hour(n: sliderValue % 24);
    return '$day $hour';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;

    // Both tabs add a profile, so they share the name field: a profile named in
    // one is still named after switching, and the form fields below are the only
    // thing that changes. Keeping the name outside the tabs says so.
    final nameController = useTextEditingController();

    final tabController = useTabController(initialLength: 2);
    final isAutoUpdateDisable = useState<bool>(false);
    final updateInterval = useState(.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 12),
          child: Row(
            children: [
              Expanded(child: Text(t.common.manually, style: theme.textTheme.headlineMedium)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => ref.read(addProfilePageNotifierProvider.notifier).goOptions(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CustomTextFormField(
            maxLines: 1,
            controller: nameController,
            validator: (value) => (value?.isEmpty ?? true) ? t.pages.profileDetails.form.emptyName : null,
            label: t.common.name,
            hint: t.pages.profileDetails.form.nameHint,
          ),
        ),
        const Gap(12),
        TabBar(
          controller: tabController,
          tabs: [
            Tab(text: t.common.url),
            Tab(text: t.pages.profileDetails.form.customProxy),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [
              _SubscriptionUrlForm(
                nameController: nameController,
                isAutoUpdateDisable: isAutoUpdateDisable,
                updateInterval: updateInterval,
                sliderText: _genSliderText(t, updateInterval.value.round()),
              ),
              CustomProxyForm(nameController: nameController),
            ],
          ),
        ),
      ],
    );
  }
}

/// The subscription URL tab: what a profile config is fetched from, and how often.
///
/// The auto-update section is only about a remote config. A custom proxy has
/// nothing to fetch, so it lives here rather than on the other tab.
class _SubscriptionUrlForm extends HookConsumerWidget {
  const _SubscriptionUrlForm({
    required this.nameController,
    required this.isAutoUpdateDisable,
    required this.updateInterval,
    required this.sliderText,
  });

  final TextEditingController nameController;
  final ValueNotifier<bool> isAutoUpdateDisable;
  final ValueNotifier<double> updateInterval;
  final String sliderText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final urlController = useTextEditingController();
    final sliderFocusNode = useFocusNode(
      onKeyEvent: (node, event) {
        if (KeyboardConst.verticalArrows.contains(event.logicalKey) && event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            node.previousFocus();
          } else {
            node.nextFocus();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Gap(12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CustomTextFormField(
              maxLines: 1,
              controller: urlController,
              validator: (value) => (value != null && !isUrl(value)) ? t.pages.profileDetails.form.invalidUrl : null,
              label: t.common.url,
              hint: t.pages.profileDetails.form.urlHint,
            ),
          ),
          const Gap(12),
          SwitchListTile.adaptive(
            title: Text(
              t.pages.profileDetails.form.disableAutoUpdate,
              style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.onSurface),
            ),
            value: isAutoUpdateDisable.value,
            onChanged: (value) => isAutoUpdateDisable.value = value,
          ),
          AnimatedSize(
            alignment: Alignment.topCenter,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: !isAutoUpdateDisable.value
                ? Column(
                    children: [
                      const Divider(indent: 16, endIndent: 16),
                      const Gap(12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.pages.profileDetails.form.autoUpdateInterval,
                                style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.onSurface),
                              ),
                            ),
                            Text(
                              sliderText,
                              style: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const Gap(4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Slider(
                          focusNode: sliderFocusNode,
                          value: updateInterval.value,
                          max: 96,
                          divisions: 96,
                          label: updateInterval.value.round().toString(),
                          onChanged: (double value) => updateInterval.value = value,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(top: 12, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    child: Text(t.common.add),
                    onPressed: () async {
                      await ref
                          .read(addProfileNotifierProvider.notifier)
                          .addManual(
                            url: urlController.text.trim(),
                            userOverride: UserOverride(
                              name: nameController.text.trim(),
                              isAutoUpdateDisable: isAutoUpdateDisable.value,
                              updateInterval: updateInterval.value.round().toInt(),
                            ),
                          );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
