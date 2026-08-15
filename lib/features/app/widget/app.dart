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
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/appearance_options.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/backup/data/backup_scheduler.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/connection/widget/connection_wrapper.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_service_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/proxy/notifier/active_proxy_blacklist_guard.dart';
import 'package:hiddify/features/proxy/notifier/node_blacklist_controller.dart';
import 'package:hiddify/features/shortcut/shortcut_wrapper.dart';
import 'package:hiddify/features/shortcut/notifier/global_hotkey_notifier.dart';
import 'package:hiddify/features/stats/notifier/traffic_history_recorder.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/features/window/widget/window_wrapper.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';
import 'package:upgrader/upgrader.dart';

bool _debugAccessibility = false;
bool isOnPauseCalled = false;

class App extends HookConsumerWidget with WidgetsBindingObserver, PresLogger {
  const App({super.key});

  void onInactive(WidgetRef ref) {
    onPause(ref);
  }

  void onPause(WidgetRef ref) {
    if (PlatformUtils.isDesktop) return;
    isOnPauseCalled = true;
    ref.read(hiddifyCoreServiceProvider).closeFront();
  }

  void onResume(WidgetRef ref) {
    // if (PlatformUtils.isDesktop) return;
    ref.read(hiddifyCoreServiceProvider).init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isOnPauseCalled && PlatformUtils.isAndroid) ref.invalidate(perAppProxyServiceProvider);
      isOnPauseCalled = false;
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    setupStateListener(ref);
    final router = ref.watch(goRouterNotiferProvider);
    final locale = ref.watch(localePreferencesProvider);
    final themeMode = ref.watch(themePreferencesProvider);
    final textScaleMode = ref.watch(AppearanceOptions.textScaleMode);
    final colorSource = ref.watch(AppearanceOptions.colorSource);
    final seedColor = Color(ref.watch(AppearanceOptions.seedColorValue));
    final theme = AppTheme(themeMode, locale.preferredFontFamily, seedColor: seedColor);
    final upgrader = ref.watch(upgraderProvider);
    final activeBreakpoint = Breakpoint(context).activeBreakpoint;

    ref.listen(nodeBlacklistControllerProvider, (_, next) async {
      if (!ref.read(serviceRunningProvider)) return;
      final activeProfile = await ref.read(activeProfileProvider.future);
      await ref.read(connectionNotifierProvider.notifier).reconnect(activeProfile);
    });
    ref.listen(activeProxyBlacklistGuardProvider, (_, _) {});
    ref.listen(foregroundProfilesUpdateNotifierProvider, (_, _) {});
    if (PlatformUtils.isAndroid) ref.listen(perAppProxyServiceProvider, (_, _) {});
    if (PlatformUtils.isDesktop) ref.listen(systemTrayNotifierProvider, (_, _) {});
    if (PlatformUtils.isDesktop) ref.listen(globalHotkeyNotifierProvider, (_, _) {});
    ref.listen(trafficHistoryRecorderProvider, (_, _) {});
    ref.listen(backupSchedulerProvider, (_, _) {});

    // updating ActiveBreakpointNotifier value
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeBreakpointNotifierProvider.notifier).update(activeBreakpoint);
      });
      return null;
    }, [activeBreakpoint]);
    return WindowWrapper(
      ShortcutWrapper(
        ToastificationWrapper(
          child: ConnectionWrapper(
            DynamicColorBuilder(
              builder: (ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
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
                    final safeChild = child ?? const SizedBox();
                    child = textScaleMode == AppTextScaleMode.system
                        ? safeChild
                        : MediaQuery(
                            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScaleMode.scale)),
                            child: safeChild,
                          );
                    child = UpgradeAlert(
                      upgrader: upgrader,
                      navigatorKey: router.routerDelegate.navigatorKey,
                      child: child,
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
  //                           theme: theme.lightTheme(lightColorScheme),
  //                           darkTheme: theme.darkTheme(darkColorScheme),
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
    final appLifecycleState = useAppLifecycleState();

    useEffect(() {
      loggy.info("current app state");
      loggy.info(appLifecycleState);
      if (appLifecycleState == AppLifecycleState.paused) {
        onPause(ref);
      } else if (appLifecycleState == AppLifecycleState.inactive) {
        onInactive(ref);
      } else if (appLifecycleState == AppLifecycleState.resumed) {
        onResume(ref);
      }
      return null;
    }, [appLifecycleState]);
  }
}
