import 'dart:convert';
import 'dart:io';

import 'package:hiddify/features/proxy/model/node_blacklist.dart';

class NodeBlacklistRepository {
  const NodeBlacklistRepository(this.file);

  final File file;

  NodeBlacklistDocument load() {
    if (!file.existsSync()) {
      return const NodeBlacklistDocument(version: 1, globalRules: [], providers: {});
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return NodeBlacklistDocument.fromJson(json);
  }

  Future<void> save(NodeBlacklistDocument document) async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(document.toJson()), flush: true);
  }
}
