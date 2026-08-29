import 'dart:convert';

import 'package:hiddify/features/profile/model/profile_entity.dart';

class ProfileExportBundle {
  const ProfileExportBundle({
    required this.name,
    required this.config,
    required this.lastUpdate,
    this.sourceUrl,
    this.subscriptionInfo,
  });

  static const format = 'hiddify-profile';
  static const version = 1;

  final String name;
  final Object? config;
  final DateTime lastUpdate;
  final String? sourceUrl;
  final SubscriptionInfo? subscriptionInfo;

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': format,
    'version': version,
    'profile': {
      'name': name,
      'sourceUrl': sourceUrl,
      'lastUpdate': lastUpdate.toIso8601String(),
      if (subscriptionInfo case final info?)
        'subscriptionInfo': {
          'upload': info.upload,
          'download': info.download,
          'total': info.total,
          'expire': info.expire.toIso8601String(),
          'webPageUrl': info.webPageUrl,
          'supportUrl': info.supportUrl,
        },
    },
    'config': config,
  });

  static ProfileExportBundle? tryDecode(String input) {
    try {
      final root = jsonDecode(input);
      if (root is! Map<String, dynamic> || root['format'] != format || root['version'] != version) return null;
      final profile = root['profile'];
      if (profile is! Map<String, dynamic> || profile['name'] is! String || !root.containsKey('config')) return null;
      final subscription = profile['subscriptionInfo'];
      SubscriptionInfo? subscriptionInfo;
      if (subscription is Map<String, dynamic>) {
        subscriptionInfo = SubscriptionInfo(
          upload: subscription['upload'] as int,
          download: subscription['download'] as int,
          total: subscription['total'] as int,
          expire: DateTime.parse(subscription['expire'] as String),
          webPageUrl: subscription['webPageUrl'] as String?,
          supportUrl: subscription['supportUrl'] as String?,
        );
      }
      return ProfileExportBundle(
        name: profile['name'] as String,
        sourceUrl: profile['sourceUrl'] as String?,
        lastUpdate: DateTime.parse(profile['lastUpdate'] as String),
        subscriptionInfo: subscriptionInfo,
        config: root['config'],
      );
    } on Object {
      return null;
    }
  }

  String get configJson => jsonEncode(config);
}
