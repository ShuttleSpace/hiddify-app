import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/model/proxy_search_result.dart';
import 'package:hiddify/features/proxy/widget/proxy_search_overlay.dart';

void main() {
  testWidgets('search overlay reports the selected result', (tester) async {
    const first = ProxySearchResult(groupTag: 'group-a', nodeTag: 'node-a', delay: 24);
    const second = ProxySearchResult(groupTag: 'group-b', nodeTag: 'node-b', delay: 42);
    ProxySearchResult? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProxySearchOverlay(
            results: [first, second],
            onSelected: (result) => selected = result,
          ),
        ),
      ),
    );

    await tester.tap(find.text('group-b'));
    expect(selected, second);
  });
}
