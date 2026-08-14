import 'package:flutter/material.dart';
import 'package:hiddify/features/per_app_proxy/domain/per_app_proxy_summary.dart';

class PerAppProxySummaryView extends StatelessWidget {
  const PerAppProxySummaryView({super.key, required this.summary});

  final PerAppProxySummary summary;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${summary.active} active · ${summary.userSelected} user · ${summary.autoSelected} auto · ${summary.forceDeselected} forced',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
