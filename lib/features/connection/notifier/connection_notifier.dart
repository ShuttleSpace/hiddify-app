import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/platform_specific/shell_proxy_env.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

part 'connection_notifier.g.dart';

@Riverpod(keepAlive: true)
class ConnectionNotifier extends _$ConnectionNotifier with AppLogger {
  @override
  Stream<ConnectionStatus> build() async* {
    if (Platform.isIOS) {
      await _connectionRepo.setup().mapLeft((l) {
        loggy.error("error setting up connection repository", l);
      }).run();
    }

    listenSelf((previous, next) async {
      if (previous == next) return;
      if (previous case AsyncData(:final value) when !value.isConnected) {
        if (next case AsyncData(value: final Connected _)) {
          await ref.read(hapticServiceProvider.notifier).heavyImpact();

          if (Platform.isAndroid && !ref.read(Preferences.storeReviewedByUser)) {
            if (await InAppReview.instance.isAvailable()) {
              InAppReview.instance.requestReview();
              ref.read(Preferences.storeReviewedByUser.notifier).update(true);
            }
          }
        }
      }
    });

    ref.listen(activeProfileProvider.select((value) => value.asData?.value), (previous, next) async {
      if (previous == null) return;
      final shouldReconnect = next == null || previous.id != next.id;
      if (shouldReconnect) {
        await reconnect(next);
      }
    });

    ref.listen(ConfigOptions.serviceMode, (previous, next) {
      if (previous != ServiceMode.systemProxy || next == ServiceMode.systemProxy) return;
      unawaited(_releaseSystemProxyForModeChange());
    });

    ref.watch(coreRestartSignalProvider);

    yield* _connectionRepo.watchConnectionStatus().doOnData((event) {
      if (event case Disconnected(connectionFailure: final _?) when PlatformUtils.isDesktop) {
        Future.microtask(() => ref.read(Preferences.startedByUser.notifier).update(false));
      }
      loggy.info("connection status: ${event.format()}");
    });
  }

  ConnectionRepository get _connectionRepo => ref.read(connectionRepositoryProvider);

  Future<void> mayConnect() async {
    if (state case AsyncData(:final value)) {
      if (value case Disconnected()) return _connect();
    }
  }

  Future<void> toggleConnection() async {
    final haptic = ref.read(hapticServiceProvider.notifier);
    if (state case AsyncError()) {
      await haptic.lightImpact();
      await _connect();
    } else if (state case AsyncData(:final value)) {
      switch (value) {
        case Disconnected():
          await haptic.lightImpact();
          await ref.read(Preferences.startedByUser.notifier).update(true);
          await _connect();
        case Connected():
          // default:
          await haptic.mediumImpact();
          await ref.read(Preferences.startedByUser.notifier).update(false);
          await _disconnect();
        default:
          loggy.warning("switching status, debounce");
      }
    }
  }

  Future<void> reconnect(ProfileEntity? profile) async {
    if (state case AsyncData(:final value) when value == const Connected()) {
      if (profile == null) {
        loggy.info("no active profile, disconnecting");
        return _disconnect();
      }
      loggy.info("active profile changed, reconnecting");
      final disableMemoryLimit = ref.read(Preferences.disableMemoryLimit);
      final dialogNotifier = ref.read(dialogNotifierProvider.notifier);
      final translations = ref.read(translationsProvider);
      await ref.read(Preferences.startedByUser.notifier).update(true);
      await _connectionRepo.reconnect(profile, disableMemoryLimit).mapLeft((err) async {
        loggy.warning("error reconnecting", err);
        state = AsyncError(err, StackTrace.current);
        await dialogNotifier.showCustomAlertFromErr(err.present(translations.requireValue));
      }).run();
    }
  }

  Future<void> abortConnection() async {
    if (state case AsyncData(:final value)) {
      switch (value) {
        case Connected() || Connecting():
          loggy.debug("aborting connection");
          await _disconnect();
        default:
      }
    }
  }

  final _singleStart = SingleCall();

  Future<void> _connect() async {
    _singleStart.run(
      () async {
        await _connectThrottled();
      },
      onIgnored: () {
        loggy.debug("connect called while another connect/disconnect is still running, ignoring");
      },
    );
  }

  Future<void> _connectThrottled() async {
    final activeProfile = await ref.read(activeProfileProvider.future);
    if (activeProfile == null) {
      loggy.info("no active profile, not connecting");
      return;
    }

    final disableMemoryLimit = ref.read(Preferences.disableMemoryLimit);
    final dialogNotifier = ref.read(dialogNotifierProvider.notifier);
    final translations = ref.read(translationsProvider);
    final startedByUserNotifier = ref.read(Preferences.startedByUser.notifier);
    await _connectionRepo.connect(activeProfile, disableMemoryLimit).mapLeft((
      ConnectionFailure err,
    ) async {
      loggy.warning("error connecting", err);
      await dialogNotifier.showCustomAlertFromErr(err.present(translations.requireValue));
      loggy.warning(err);
      if (err.toString().contains("panic")) {
        await Sentry.captureException(Exception(err.toString()));
      }
      await startedByUserNotifier.update(false);
      state = AsyncError(err, StackTrace.current);
    }).run();
  }

  Future<void> _disconnect() async {
    final dialogNotifier = ref.read(dialogNotifierProvider.notifier);
    final translations = ref.read(translationsProvider);
    await _connectionRepo.disconnect().mapLeft((err) {
      dialogNotifier.showCustomAlertFromErr(err.present(translations.requireValue));
      state = AsyncError(err, StackTrace.current);
    }).run();
    unawaited(_announceDisconnect(translations));
  }

  /// Leaving system-proxy mode while connected has to reach the OS by hand. The
  /// tunnel stays up, so nothing is closed and the inbound that owns the proxy
  /// never gets to clean up after itself, yet the mode the user just picked says
  /// the OS should not be proxied. Nothing to do when we were never proxying.
  Future<void> _releaseSystemProxyForModeChange() async {
    if (state case AsyncData(:final value) when !value.isConnected) return;
    loggy.info("leaving system proxy mode while connected, releasing the os proxy");
    await _connectionRepo.releaseSystemProxy().mapLeft((err) {
      loggy.warning("failed to release the system proxy after a mode change", err);
    }).run();
  }

  /// Releasing the macOS system proxy changes nothing the user can see: no window
  /// closes, no tray badge clears, the toggle they flipped just goes back. Say it
  /// happened instead of leaving them to check System Settings for it.
  ///
  /// Nothing here dismisses what is already on screen. The shell hint is a second
  /// thing to say about the same event, and replacing the first with it would hide
  /// the first.
  Future<void> _announceDisconnect(AsyncValue<Translations> translations) async {
    if (!Platform.isMacOS) return;
    // The core has already stopped by now. A toast that cannot be worded is not
    // worth failing the disconnect over, and requiring here would do exactly that.
    final t = translations.valueOrNull;
    if (t == null) return;
    final notifications = ref.read(inAppNotificationControllerProvider);
    if (ref.read(ConfigOptions.serviceMode) == ServiceMode.systemProxy) {
      notifications.showInfoToast(t.connection.systemProxyReleased, replaceExisting: false);
    }
    await _warnAboutShellProxyEnv(t);
  }

  bool _warnedAboutShellProxyEnv = false;

  /// Shells that exported HTTP_PROXY keep pointing at the mixed port after we
  /// stop, and nothing we do can reach into a process we do not own. Say what to
  /// run instead. Once per session is enough, and only when a profile shows the
  /// user actually set one up.
  Future<void> _warnAboutShellProxyEnv(Translations translations) async {
    if (_warnedAboutShellProxyEnv) return;
    if (!await ShellProxyEnv.anyProfileExportsProxy()) return;
    _warnedAboutShellProxyEnv = true;
    final mixedPort = ref.read(ConfigOptions.mixedPort);
    loggy.info("shell proxy env detected on disconnect, hinting cleanup for port $mixedPort");
    ref
        .read(inAppNotificationControllerProvider)
        .showInfoToast(
          translations.connection.shellProxyEnv(port: mixedPort),
          duration: const Duration(seconds: 10),
          replaceExisting: false,
        );
  }
}

@Riverpod(keepAlive: true)
bool serviceRunning(Ref ref) {
  // ref.watch(coreRestartSignalProvider);
  return ref.watch(connectionNotifierProvider).valueOrNull?.isConnected ?? false;
}

class SingleCall {
  bool _running = false;

  Future<T> run<T>(Future<T> Function() task, {required T onIgnored}) async {
    if (_running) return onIgnored;

    _running = true;
    try {
      return await task();
    } finally {
      _running = false;
    }
  }
}

/// Whether the core is hot reloading; only the connection button shows it.
final hotReloadingProvider = StreamProvider<bool>(
  (ref) => ref.watch(connectionRepositoryProvider).watchHotReloading(),
);
