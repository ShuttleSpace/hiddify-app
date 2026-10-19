import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/details/json_editor.dart';

/// The tree editor writes edited values into its data model on focus loss and
/// only notifies its parent through a debounce timer, so saving straight from a
/// focused field used to persist the pre-edit content. [JsonEditorState.flush]
/// must commit that pending edit synchronously.
void main() {
  const config = '''
{
  "outbounds": [
    {"type": "http", "tag": "proxy", "server": "127.0.0.1", "server_port": 8080}
  ],
  "endpoints": []
}
''';

  Future<dynamic> pumpEditor(
    WidgetTester tester,
    GlobalKey<JsonEditorState> key,
    void Function(dynamic) onChanged,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JsonEditor(
            key: key,
            json: config,
            expandedObjects: const [
              ["outbounds", 0],
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('flush commits the value of the focused field', (tester) async {
    final key = GlobalKey<JsonEditorState>();
    Map<String, dynamic>? emitted;
    await pumpEditor(tester, key, (value) => emitted = value as Map<String, dynamic>);

    await tester.tap(find.text('proxy'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'not-proxy');
    // Deliberately do not wait for the 500ms debounce.

    expect(emitted, isNull, reason: 'nothing is emitted while just typing');

    expect(key.currentState!.flush(), isTrue);
    await tester.pump();

    expect(emitted, isNotNull);
    final outbounds = emitted!['outbounds'] as List;
    final outbound = outbounds[0] as Map<String, dynamic>;
    expect(outbound['tag'], 'not-proxy');
  });

  testWidgets('flush commits a numeric edit without losing its type', (tester) async {
    final key = GlobalKey<JsonEditorState>();
    Map<String, dynamic>? emitted;
    await pumpEditor(tester, key, (value) => emitted = value as Map<String, dynamic>);

    await tester.tap(find.text('8080'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '9090');
    expect(key.currentState!.flush(), isTrue);
    await tester.pump();

    final outbounds = emitted!['outbounds'] as List;
    final outbound = outbounds[0] as Map<String, dynamic>;
    expect(outbound['server_port'], 9090);
  });

  testWidgets('flush rejects invalid JSON from the text editor', (tester) async {
    final key = GlobalKey<JsonEditorState>();
    Map<String, dynamic>? emitted;
    await pumpEditor(tester, key, (value) => emitted = value as Map<String, dynamic>);

    // Switch to the text editor via the header menu.
    await tester.tap(find.text('tree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '{ not json');

    expect(key.currentState!.flush(), isFalse);
    expect(emitted, isNull);
  });
}
