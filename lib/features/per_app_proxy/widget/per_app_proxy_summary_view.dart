import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/per_app_proxy/domain/per_app_proxy_summary.dart';

class PerAppProxySummaryView extends StatelessWidget {
  const PerAppProxySummaryView({super.key, required this.summary, required this.t});

  final PerAppProxySummary summary;
  final Translations t;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${t.pages.settings.routing.generalOptions.perAppProxy.summary.active(n: summary.active)}'
      ' · ${t.pages.settings.routing.generalOptions.perAppProxy.summary.user(n: summary.userSelected)}'
      ' · ${t.pages.settings.routing.generalOptions.perAppProxy.summary.auto(n: summary.autoSelected)}'
      ' · ${t.pages.settings.routing.generalOptions.perAppProxy.summary.forced(n: summary.forceDeselected)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
