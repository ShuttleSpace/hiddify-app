import 'dart:async';

import 'package:hiddify/features/log/data/log_data_providers.dart';
import 'package:hiddify/features/log/model/log_entity.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/log/overview/logs_overview_state.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';

part 'logs_overview_notifier.g.dart';

enum LogSource { core, app }

final logSourceProvider = StateProvider<LogSource>((ref) => LogSource.core);

@riverpod
class LogsOverviewNotifier extends _$LogsOverviewNotifier with AppLogger {
  @override
  LogsOverviewState build() {
    ref.disposeDelay(const Duration(seconds: 20));
    state = const LogsOverviewState();
    ref.onDispose(() {
      loggy.debug("disposing");
      _coreListener?.cancel();
      _appListener?.cancel();
      _coreListener = null;
      _appListener = null;
    });
    ref.onCancel(() {
      if (_coreListener?.isPaused != true) {
        loggy.debug("pausing");
        _coreListener?.pause();
        _appListener?.pause();
      }
    });
    ref.onResume(() {
      if (!state.paused && (_coreListener?.isPaused ?? false)) {
        loggy.debug("resuming");
        _coreListener?.resume();
        _appListener?.resume();
      }
    });

    _addListeners();
    return const LogsOverviewState();
  }

  StreamSubscription? _coreListener;
  StreamSubscription? _appListener;

  Future<void> _addListeners() async {
    loggy.debug("adding listeners");
    ref.watch(coreRestartSignalProvider);
    await _coreListener?.cancel();
    await _appListener?.cancel();
    state = state.copyWith(logs: const AsyncData([]));
    final repo = ref.read(logRepositoryProvider).requireValue;

    _coreListener = repo
        .watchCoreLogs()
        .throttle((_) => Stream.value(_coreListener?.isPaused ?? false), leading: false, trailing: true)
        .throttleTime(const Duration(milliseconds: 250), leading: false, trailing: true)
        .asyncMap((event) async {
          await event.fold(
            (f) {
              _coreLogs = [];
              if (ref.read(logSourceProvider) == LogSource.core) {
                state = state.copyWith(logs: AsyncError(f, StackTrace.current));
              }
            },
            (a) async {
              _coreLogs = a.reversed.toList();
              if (ref.read(logSourceProvider) == LogSource.core) {
                state = state.copyWith(logs: AsyncData(await _computeLogs()));
              }
            },
          );
        })
        .listen((_) {});

    _appListener = repo
        .watchAppLogs()
        .throttle((_) => Stream.value(_appListener?.isPaused ?? false), leading: false, trailing: true)
        .throttleTime(const Duration(milliseconds: 250), leading: false, trailing: true)
        .asyncMap((event) async {
          await event.fold(
            (f) {
              _appLogs = [];
              if (ref.read(logSourceProvider) == LogSource.app) {
                state = state.copyWith(logs: AsyncError(f, StackTrace.current));
              }
            },
            (a) async {
              _appLogs = a.reversed.toList();
              if (ref.read(logSourceProvider) == LogSource.app) {
                state = state.copyWith(logs: AsyncData(await _computeLogs()));
              }
            },
          );
        })
        .listen((_) {});
  }

  List<LogEntity> _coreLogs = [];
  List<LogEntity> _appLogs = [];
  final _debouncer = CallbackDebouncer(const Duration(milliseconds: 200));
  LogLevel? _levelFilter;
  String _filter = "";

  Future<List<LogEntity>> _computeLogs() async {
    final logs = ref.read(logSourceProvider) == LogSource.core ? _coreLogs : _appLogs;
    if (_levelFilter == null && _filter.isEmpty) return logs;
    return logs.where((e) {
      return (_filter.isEmpty || e.message.contains(_filter)) &&
          (_levelFilter == null || e.level == null || e.level!.index >= _levelFilter!.index);
    }).toList();
  }

  Future<void> setSource(LogSource source) async {
    ref.read(logSourceProvider.notifier).state = source;
    state = state.copyWith(logs: AsyncData(await _computeLogs()));
  }

  void pause() {
    loggy.debug("pausing");
    _coreListener?.pause();
    _appListener?.pause();
    state = state.copyWith(paused: true);
  }

  void resume() {
    loggy.debug("resuming");
    _coreListener?.resume();
    _appListener?.resume();
    state = state.copyWith(paused: false);
  }

  Future<void> clear() async {
    loggy.debug("clearing");
    await ref
        .read(logRepositoryProvider)
        .requireValue
        .clearLogs()
        .match(
          (l) {
            loggy.warning("error clearing logs", l);
          },
          (_) {
            _coreLogs = [];
            _appLogs = [];
            state = state.copyWith(logs: const AsyncData([]));
          },
        )
        .run();
  }

  void filterMessage(String? filter) {
    _filter = filter ?? '';
    _debouncer(() async {
      if (state.logs case AsyncData()) {
        state = state.copyWith(filter: _filter, logs: AsyncData(await _computeLogs()));
      }
    });
  }

  Future<void> filterLevel(LogLevel? level) async {
    _levelFilter = level;
    if (state.logs case AsyncData()) {
      state = state.copyWith(levelFilter: _levelFilter, logs: AsyncData(await _computeLogs()));
    }
  }
}
