import 'dart:convert';

import 'package:hiddify/features/proxy/model/node_blacklist.dart';

String exportToJson(NodeBlacklistDocument document) {
  return const JsonEncoder.withIndent('  ').convert(document.toJson());
}

NodeBlacklistDocument importFromJson(String input) {
  return NodeBlacklistDocument.fromJson(jsonDecode(input) as Map<String, dynamic>);
}

String exportDeepLink(NodeBlacklistDocument document) {
  final data = base64Encode(utf8.encode(exportToJson(document)));
  return 'hiddify://settings/node-blacklist?data=$data';
}

NodeBlacklistDocument importFromDeepLink(String deepLink) {
  final data = Uri.parse(deepLink).queryParameters['data'];
  if (data == null) throw const FormatException('Missing data');
  return importFromJson(utf8.decode(base64Decode(data)));
}

List<String> plainTextLines(String input) {
  return input
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}
