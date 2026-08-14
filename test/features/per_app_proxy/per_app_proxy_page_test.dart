import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/per_app_proxy/domain/per_app_proxy_summary.dart';
import 'package:hiddify/features/per_app_proxy/widget/per_app_proxy_summary_view.dart';

void main() {
  testWidgets('summary view renders counts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PerAppProxySummaryView(
            summary: const PerAppProxySummary(
              active: 12,
              userSelected: 10,
              autoSelected: 2,
              forceDeselected: 1,
            ),
            t: AppLocale.en.buildSync(),
          ),
        ),
      ),
    );
    expect(find.textContaining('12 active'), findsOneWidget);
    expect(find.textContaining('10 user'), findsOneWidget);
    expect(find.textContaining('2 auto'), findsOneWidget);
    expect(find.textContaining('1 forced'), findsOneWidget);
  });
}
