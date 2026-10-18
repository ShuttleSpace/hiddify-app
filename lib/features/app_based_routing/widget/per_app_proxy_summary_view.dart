import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/app_based_routing/domain/per_app_proxy_summary.dart';

class PerAppProxySummaryView extends StatelessWidget {
  const PerAppProxySummaryView({super.key, required this.summary, required this.t});

  final PerAppProxySummary summary;
  final Translations t;

  @override
  Widget build(BuildContext context) {
    final summaryText = t.pages.settings.routing.generalOptions.perAppProxy.summary;
    return Text(
      '${summaryText.active(n: summary.active)}'
      ' · ${summaryText.user(n: summary.userSelected)}'
      ' · ${summaryText.auto(n: summary.autoSelected)}'
      ' · ${summaryText.forced(n: summary.forceDeselected)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}