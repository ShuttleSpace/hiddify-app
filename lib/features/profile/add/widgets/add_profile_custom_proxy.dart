import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/profile/data/custom_proxy_config.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The form behind "custom proxy": an address, a port, and credentials if the
/// proxy wants them.
///
/// A locally-generated sing-box profile, so the rest of the app treats it like any
/// other local config: it can be edited, exported and removed the same way, and
/// nothing downstream has to know where the JSON came from.
class AddProfileCustomProxy extends HookConsumerWidget {
  const AddProfileCustomProxy({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final nameController = useTextEditingController();
    final serverController = useTextEditingController();
    final portController = useTextEditingController(text: '1080');
    final usernameController = useTextEditingController();
    final passwordController = useTextEditingController();
    final protocol = useState(CustomProxyProtocol.socks);
    final wantsAuth = useState(false);
    final failure = useState<String?>(null);

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(t.pages.profileDetails.form.customProxy, style: theme.textTheme.headlineMedium),
                ),
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
              label: t.common.name,
              hint: t.pages.profileDetails.form.nameHint,
            ),
          ),
          const Gap(16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: CustomTextFormField(
                    maxLines: 1,
                    controller: serverController,
                    label: t.pages.profileDetails.form.server,
                    hint: t.pages.profileDetails.form.serverHint,
                  ),
                ),
                const Gap(12),
                Expanded(
                  flex: 2,
                  child: CustomTextFormField(
                    maxLines: 1,
                    controller: portController,
                    label: t.pages.profileDetails.form.port,
                    hint: '1080',
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
          ),
          const Gap(12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<CustomProxyProtocol>(
              initialValue: protocol.value,
              decoration: InputDecoration(labelText: t.pages.profileDetails.form.protocol),
              items: CustomProxyProtocol.values
                  .map((value) => DropdownMenuItem(value: value, child: Text(value.name.toUpperCase())))
                  .toList(),
              onChanged: (value) {
                if (value != null) protocol.value = value;
              },
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(
              t.pages.profileDetails.form.username,
              style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.onSurface),
            ),
            subtitle: wantsAuth.value ? null : Text(t.pages.profileDetails.form.credentialsOptional),
            value: wantsAuth.value,
            onChanged: (value) => wantsAuth.value = value,
          ),
          if (wantsAuth.value) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CustomTextFormField(
                maxLines: 1,
                controller: usernameController,
                label: t.pages.profileDetails.form.username,
              ),
            ),
            const Gap(12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CustomTextFormField(
                maxLines: 1,
                controller: passwordController,
                label: t.pages.profileDetails.form.password,
              ),
            ),
          ],
          if (failure.value case final message?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(message, style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(top: 12, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    child: Text(t.common.add),
                    onPressed: () async {
                      failure.value = CustomProxyConfig.validate(
                        server: serverController.text,
                        serverPort: portController.text,
                        username: wantsAuth.value ? usernameController.text : null,
                        password: wantsAuth.value ? passwordController.text : null,
                      );
                      if (failure.value != null) return;

                      final config = CustomProxyConfig(
                        name: nameController.text.trim().isEmpty
                            ? serverController.text.trim()
                            : nameController.text.trim(),
                        server: serverController.text.trim(),
                        serverPort: int.parse(portController.text.trim()),
                        username: wantsAuth.value ? usernameController.text.trim() : null,
                        // Auth fields are the whole form, and one of the pair being
                        // cleared would silently drop the credentials entirely.
                        password: wantsAuth.value ? passwordController.text : null,
                        protocol: protocol.value,
                      );
                      await ref
                          .read(addProfileNotifierProvider.notifier)
                          .addCustomProxy(config.encode(), config.name);
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
