import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/data/node_blacklist_repository.dart';
import 'package:hiddify/features/proxy/model/node_blacklist.dart';

void main() {
  test('repository saves and loads a document', () async {
    final dir = await Directory.systemTemp.createTemp('node-blacklist-test');
    final file = File('${dir.path}/node_blacklist.json');
    final repo = NodeBlacklistRepository(file);
    final doc = NodeBlacklistDocument(version: 1, globalRules: [], providers: const {});

    await repo.save(doc);
    expect(repo.load().version, 1);

    await dir.delete(recursive: true);
  });
}
