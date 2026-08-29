import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_export_bundle.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles_notifier.g.dart';

enum ProfileExportFormat {
  json('json'),
  yaml('yaml'),
  url('url');

  const ProfileExportFormat(this.extension);

  final String extension;
}

@riverpod
class ProfilesSortNotifier extends _$ProfilesSortNotifier with AppLogger {
  @override
  ({ProfilesSort by, SortMode mode}) build() {
    return (by: ProfilesSort.lastUpdate, mode: SortMode.descending);
  }

  void changeSort(ProfilesSort sortBy) => state = (by: sortBy, mode: state.mode);

  void toggleMode() =>
      state = (by: state.by, mode: state.mode == SortMode.ascending ? SortMode.descending : SortMode.ascending);
}

@riverpod
class ProfilesNotifier extends _$ProfilesNotifier with AppLogger {
  @override
  Stream<List<ProfileEntity>> build() {
    final sort = ref.watch(profilesSortNotifierProvider);
    return _profilesRepo.watchAll(sort: sort.by, sortMode: sort.mode).map((event) => event.getOrElse((l) => throw l));
  }

  ProfileRepository get _profilesRepo => ref.read(profileRepositoryProvider).requireValue;

  Future<Unit> selectActiveProfile(String id) async {
    loggy.debug('changing active profile to: [$id]');
    await ref.read(hapticServiceProvider.notifier).lightImpact();
    return _profilesRepo.setAsActive(id).getOrElse((err) {
      loggy.warning('failed to set [$id] as active profile', err);
      throw err;
    }).run();
  }

  Future<void> deleteProfile(ProfileEntity profile) async {
    loggy.debug('deleting profile: ${profile.name}');

    if (profile.active) await ref.read(connectionNotifierProvider.notifier).abortConnection();
    await _profilesRepo
        .deleteById(profile.id, profile.active)
        .match(
          (err) {
            loggy.warning('failed to delete profile', err);
            throw err;
          },
          (_) async {
            loggy.info('successfully deleted profile, was active? [${profile.active}]');
            final t = ref.read(translationsProvider).requireValue;
            ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.profiles.msg.delete.success);

            final activePrfile = await ref.read(activeProfileProvider.future);
            if (profile.id == ref.read(ConfigOptions.extraSecurityProfileId)) {
              ref.read(ConfigOptions.extraSecurityProfileId.notifier).update(activePrfile?.id);
            }
            if (profile.id == ref.read(ConfigOptions.unblockerProfileId)) {
              ref.read(ConfigOptions.unblockerProfileId.notifier).update(activePrfile?.id);
            }

            return unit;
          },
        )
        .run();
  }

  Future<void> exportConfigToClipboard(ProfileEntity profile) async {
    await _profilesRepo
        .generateConfig(profile.id)
        .match(
          (err) {
            loggy.warning('error generating config', err);
            throw err;
          },
          (configJson) async {
            await Clipboard.setData(ClipboardData(text: configJson));
            final t = ref.read(translationsProvider).requireValue;
            ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.clipboard.success);
          },
        )
        .run();
  }

  Future<bool> exportProfileToFile(ProfileEntity profile, ProfileExportFormat format) async {
    final t = ref.read(translationsProvider).requireValue;
    try {
      final defaultName = '${_safeFileName(profile.name)}.${format.extension}';
      final fileName = await ref
          .read(dialogNotifierProvider.notifier)
          .showSettingInput<String>(
            title: '文件名',
            initialValue: defaultName,
            icon: Icons.drive_file_rename_outline_rounded,
            validator: (value) => value.trim().isNotEmpty,
          );
      if (fileName == null) return false;

      final normalizedName = _ensureExtension(_safeFileName(fileName), format.extension);
      final content = await _exportContent(profile, format);
      final bytes = utf8.encode(content);
      final outputFile = await FilePicker.platform.saveFile(
        fileName: normalizedName,
        type: FileType.custom,
        allowedExtensions: [format.extension],
        bytes: bytes,
      );
      if (outputFile == null) return false;
      // On mobile, file_picker writes [bytes] through the platform document
      // provider. Its returned value is not guaranteed to be a path that can
      // be reopened with dart:io (for example, an Android SAF document URI).
      // Desktop pickers only select the destination, so persist the bytes
      // ourselves there.
      if (PlatformUtils.isDesktop) {
        final file = File(_ensureExtension(outputFile, format.extension));
        if (!await file.parent.exists()) await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.file.success);
      return true;
    } catch (e, st) {
      loggy.warning('error exporting profile to ${format.extension} file', e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.export.file.failure);
      return false;
    }
  }

  Future<String> _exportContent(ProfileEntity profile, ProfileExportFormat format) async {
    if (format == ProfileExportFormat.url) {
      if (profile case RemoteProfileEntity(:final url, :final name)) {
        return LinkParser.generateSubShareLink(url, name);
      }
      throw const ProfileFailure.unexpected('local profile does not have a subscription URL');
    }

    final configJson = await _profilesRepo.generateConfig(profile.id).match((err) {
      loggy.warning('error generating config', err);
      throw err;
    }, (configJson) => configJson).run();
    if (format == ProfileExportFormat.json) {
      return ProfileExportBundle(
        name: profile.name,
        sourceUrl: profile is RemoteProfileEntity ? profile.url : null,
        lastUpdate: profile.lastUpdate,
        subscriptionInfo: profile is RemoteProfileEntity ? profile.subInfo : null,
        config: jsonDecode(configJson),
      ).encode();
    }
    return _jsonToYaml(jsonDecode(configJson));
  }

  String _safeFileName(String value) {
    final fileName = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
    return fileName.isEmpty ? 'profile' : fileName;
  }

  String _ensureExtension(String value, String extension) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase().endsWith('.$extension')) return trimmed;
    return '$trimmed.$extension';
  }

  String _jsonToYaml(Object? value, [int indent = 0]) {
    final buffer = StringBuffer();
    _writeYaml(buffer, value, indent);
    return buffer.toString();
  }

  void _writeYaml(StringBuffer buffer, Object? value, int indent) {
    final padding = ' ' * indent;
    switch (value) {
      case final Map<String, dynamic> map:
        for (final entry in map.entries) {
          buffer.write('$padding${_yamlScalar(entry.key)}:');
          if (_isYamlCollection(entry.value)) {
            buffer.writeln();
            _writeYaml(buffer, entry.value, indent + 2);
          } else {
            buffer.writeln(' ${_yamlScalar(entry.value)}');
          }
        }
      case final List<dynamic> list:
        for (final item in list) {
          buffer.write('$padding-');
          if (_isYamlCollection(item)) {
            buffer.writeln();
            _writeYaml(buffer, item, indent + 2);
          } else {
            buffer.writeln(' ${_yamlScalar(item)}');
          }
        }
      default:
        buffer.writeln('$padding${_yamlScalar(value)}');
    }
  }

  bool _isYamlCollection(Object? value) => value is Map || value is List;

  String _yamlScalar(Object? value) {
    if (value == null) return 'null';
    if (value is num || value is bool) return value.toString();
    return jsonEncode(value.toString());
  }
}
