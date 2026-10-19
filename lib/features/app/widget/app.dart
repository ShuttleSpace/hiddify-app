import 'package:accessibility_tools/accessibility_tools.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/app_based_routing/overview/app_based_routing_notifier.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/connection/widget/connection_wrapper.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/shortcut/shortcut_wrapper.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/features/window/widget/window_wrapper.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/features/proxy/notifier/active_proxy_blacklist_guard.dart';
import 'package:hiddify/features/stats/notifier/traffic_history_recorder.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hiddify/core/theme/appearance_options.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:upgrader/upgrader.dart';

bool _debugAccessibility = false;
bool isOnPauseCalled = false;

class App extends HookConsumerWidget with WidgetsBindingObserver, PresLogger {
  const App({super.key});

  void onPause(WidgetRef ref) {
    if (PlatformUtils.isDesktop) return;
    isOnPauseCalled = true;
    ref.read(hiddifyCoreServiceProvider).closeFront();
  }

  void onResume(WidgetRef ref) {
    // if (PlatformUtils.isDesktop) return;
    ref.read(hiddifyCoreServiceProvider).init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isOnPauseCalled && PlatformUtils.isAndroid) ref.invalidate(appBasedRoutingProvider);
      isOnPauseCalled = false;
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    setupStateListener(ref);
    final router = ref.watch(goRouterNotiferProvider);
    final locale = ref.watch(localePreferencesProvider);
    final themeMode = ref.watch(themePreferencesProvider);
    // The appearance page offers the wallpaper's colours, a colour of the user's
    // picking, and the built-in one. Each has to reach the scheme: reading the
    // preference and then building the theme from the hardcoded seed alone left
    // the swatches in the settings page changing nothing on screen.
    final colorSource = ref.watch(AppearanceOptions.colorSource);
    final seedColor = Color(ref.watch(AppearanceOptions.seedColorValue));
    final theme = AppTheme(themeMode, locale.preferredFontFamily, seedColor: seedColor);
    final upgrader = ref.watch(upgraderProvider);
    final activeBreakpoint = Breakpoint(context).activeBreakpoint;

    ref.listen(foregroundProfilesUpdateNotifierProvider, (_, _) {});
    if (PlatformUtils.isAndroid) ref.listen(appBasedRoutingProvider, (_, _) {});
    if (PlatformUtils.isDesktop) ref.listen(systemTrayNotifierProvider, (_, _) {});

    // Editing the blacklist can strand the node that is currently selected, so
    // it has to say so rather than leave the tunnel on a node it just banned.
    ref.listen(activeProxyBlacklistGuardProvider, (_, _) {});

    // Daily upload and download totals for the traffic history page. Nothing
    // reads the result, so the provider is started and left to run.
    ref.listen(trafficHistoryRecorderProvider, (_, _) {});

    // updating ActiveBreakpointNotifier value
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeBreakpointNotifierProvider.notifier).update(activeBreakpoint);
      });
      return null;
    }, [activeBreakpoint]);
    return WindowWrapper(
      ShortcutWrapper(
        ConnectionWrapper(
          DynamicColorBuilder(
            builder: (ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
              // A null from the builder means the platform gave us nothing, so
              // dynamic color is off. The other two sources name their scheme.
              final effectiveLight = switch (colorSource) {
                AppColorSource.dynamicColor => lightColorScheme,
                AppColorSource.seed => ColorScheme.fromSeed(seedColor: seedColor),
                AppColorSource.brand => null,
              };
              final effectiveDark = switch (colorSource) {
                AppColorSource.dynamicColor => darkColorScheme,
                AppColorSource.seed => ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark),
                AppColorSource.brand => null,
              };
              return MaterialApp.router(
                routerConfig: router,
                scaffoldMessengerKey: appScaffoldMessengerKey,
                locale: locale.flutterLocale,
                supportedLocales: AppLocaleUtils.supportedLocales,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                debugShowCheckedModeBanner: false,
                themeMode: themeMode.flutterThemeMode,
                theme: theme.lightTheme(effectiveLight),
                darkTheme: theme.darkTheme(effectiveDark),
                title: Constants.appName,
                builder: (context, child) {
                  final theme = Theme.of(context);
                  child = SnackBarHost(
                    child: UpgradeAlert(
                      upgrader: upgrader,
                      navigatorKey: router.routerDelegate.navigatorKey,
                      child: child ?? const SizedBox(),
                    ),
                  );
                  if (kDebugMode && _debugAccessibility) {
                    return AccessibilityTools(checkFontOverflows: true, child: child);
                  }
                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: SystemUiOverlayStyle(
                      statusBarColor: theme.scaffoldBackgroundColor,
                      systemNavigationBarColor: theme.scaffoldBackgroundColor,
                      systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
                          ? Brightness.light
                          : Brightness.dark,
                    ),
                    child: child,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // @override
  // Widget build1(BuildContext context, WidgetRef ref) {
  //   setupStateListener(ref);
  //   // setupQuickSettings(ref);
  //   final router = ref.watch(routerProvider);
  //   final locale = ref.watch(localePreferencesProvider);
  //   final themeMode = ref.watch(themePreferencesProvider);
  //   final theme = AppTheme(themeMode, locale.preferredFontFamily);
  //   final upgrader = ref.watch(upgraderProvider);

  //   ref.listen(foregroundProfilesUpdateNotifierProvider, (_, __) {});

  //   return WindowWrapper(
  //     TrayWrapper(
  //       ShortcutWrapper(
  //         ConnectionWrapper(
  //           PlatformProvider(
  //               settings: PlatformSettingsData(
  //                 iosUsesMaterialWidgets: true,
  //               ),
  //               builder: (context) => DynamicColorBuilder(
  //                     builder: (ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
  //                       return PlatformApp.router(
  //                         routerConfig: router,
  //                         locale: locale.flutterLocale,
  //                         supportedLocales: AppLocaleUtils.supportedLocales,
  //                         localizationsDelegates: GlobalMaterialLocalizations.delegates,
  //                         debugShowCheckedModeBanner: false,
  //                         material: (context, platform) => MaterialAppRouterData(
  //                           theme: theme.lightTheme(effectiveLight),
  //                           darkTheme: theme.darkTheme(effectiveDark),
  //                           themeMode: themeMode.flutterThemeMode,
  //                         ),
  //                         cupertino: (context, platform) {
  //                           final sysDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

  //                           return CupertinoAppRouterData(theme: theme.cupertinoThemeData(sysDark, lightColorScheme, darkColorScheme));
  //                         },
  //                         title: Constants.appName,
  //                         builder: (context, child) {
  //                           child = UpgradeAlert(
  //                             upgrader: upgrader,
  //                             navigatorKey: router.routerDelegate.navigatorKey,
  //                             child: child ?? const SizedBox(),
  //                           );
  //                           if (kDebugMode && _debugAccessibility) {
  //                             return AccessibilityTools(
  //                               checkFontOverflows: true,
  //                               child: child,
  //                             );
  //                           }
  //                           return child;
  //                         },
  //                       );
  //                     },
  //                   )),
  //         ),
  //       ),
  //     ),
  //   );
  // }

  void setupStateListener(WidgetRef ref) {
    useEffect(() {
      // The engine calls the listener directly, so a pause is seen even when no frame is drawn in the
      // background. Inactive (a dialog, the notification shade) is not a pause and closes nothing.
      void handle(AppLifecycleState state) {
        loggy.info("app state: $state");
        if (state == AppLifecycleState.paused) onPause(ref);
        if (state == AppLifecycleState.resumed) onResume(ref);
      }

      final initial = WidgetsBinding.instance.lifecycleState;
      if (initial != null) handle(initial);
      final listener = AppLifecycleListener(onStateChange: handle);
      return listener.dispose;
    }, const []);
  }
}
