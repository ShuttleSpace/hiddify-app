import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/log/data/log_parser.dart';
import 'package:hiddify/features/log/data/log_path_resolver.dart';
import 'package:hiddify/features/log/model/log_entity.dart';
import 'package:hiddify/features/log/model/log_failure.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:rxdart/rxdart.dart';

abstract interface class LogRepository {
  TaskEither<LogFailure, Unit> init();
  Stream<Either<LogFailure, List<LogEntity>>> watchCoreLogs();
  Stream<Either<LogFailure, List<LogEntity>>> watchAppLogs();
  TaskEither<LogFailure, Unit> clearLogs();
}

class LogRepositoryImpl with ExceptionHandler, InfraLogger implements LogRepository {
  LogRepositoryImpl({required this.singbox, required this.logPathResolver});

  final HiddifyCoreService singbox;
  final LogPathResolver logPathResolver;

  @override
  TaskEither<LogFailure, Unit> init() {
    return exceptionHandler(() async {
      if (!kIsWeb) {
        if (!await logPathResolver.directory.exists()) {
          await logPathResolver.directory.create(recursive: true);
        }
        await logPathResolver.coreFile().parent.create(recursive: true);
        if (!await logPathResolver.coreFile().exists()) {
          await logPathResolver.coreFile().create(recursive: true);
        }
        if (await logPathResolver.appFile().exists()) {
          await logPathResolver.appFile().writeAsString("");
        } else {
          await logPathResolver.appFile().create(recursive: true);
        }
      }
      return right(unit);
    }, LogUnexpectedFailure.new);
  }

  @override
  Stream<Either<LogFailure, List<LogEntity>>> watchCoreLogs() {
    final streamLogs = singbox
        .watchLogs(logPathResolver.coreFile().path)
        .map((event) => event.map(LogParser.parseLogProto).toList())
        .handleExceptions((error, stackTrace) {
          loggy.warning("error watching core logs", error, stackTrace);
          return LogFailure.unexpected(error, stackTrace);
        });

    final fileLogs = _watchTextLogs(
      logPathResolver.coreFile().path,
      LogParser.parseSingbox,
    ).map((logs) => right<LogFailure, List<LogEntity>>(logs));

    return Rx.combineLatest2<
      Either<LogFailure, List<LogEntity>>,
      Either<LogFailure, List<LogEntity>>,
      Either<LogFailure, List<LogEntity>>
    >(
      streamLogs.startWith(right(const [])),
      fileLogs.startWith(right(const [])),
      (stream, file) {
        if (stream.isLeft()) return stream;
        if (file.isLeft()) return file;
        final merged = [
          ...stream.getOrElse((_) => const []),
          ...file.getOrElse((_) => const []),
        ];
        return right<LogFailure, List<LogEntity>>(_dedupe(merged));
      },
    );
  }

  @override
  Stream<Either<LogFailure, List<LogEntity>>> watchAppLogs() {
    return _watchTextLogs(
      logPathResolver.appFile().path,
      (line) => LogEntity(message: line),
    ).map((logs) => right<LogFailure, List<LogEntity>>(logs));
  }

  List<LogEntity> _dedupe(List<LogEntity> logs) {
    final seen = <String>{};
    return logs.where((log) {
      final key = '${log.time?.millisecondsSinceEpoch}|${log.level?.name}|${log.message}';
      return seen.add(key);
    }).toList();
  }

  Stream<List<LogEntity>> _watchTextLogs(
    String path,
    LogEntity Function(String line) parse,
  ) {
    if (kIsWeb) return Stream.value(const <LogEntity>[]);
    final file = File(path);
    return Stream.periodic(const Duration(seconds: 1)).asyncMap((_) async {
      if (!await file.exists()) return const <LogEntity>[];
      try {
        final lines = await file.readAsLines();
        final recent = lines.length > 500 ? lines.sublist(lines.length - 500) : lines;
        return recent.where((line) => line.trim().isNotEmpty).map(parse).toList();
      } catch (_) {
        return const <LogEntity>[];
      }
    });
  }

  @override
  TaskEither<LogFailure, Unit> clearLogs() {
    return exceptionHandler(() => singbox.clearLogs().mapLeft(LogFailure.unexpected).run(), LogFailure.unexpected);
  }
}
