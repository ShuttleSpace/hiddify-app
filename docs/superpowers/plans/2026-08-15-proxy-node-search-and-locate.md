# Proxy Node Search and Locate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add cross-group node search, jump-and-highlight behavior, and automatic current-node location to the existing Hiddify proxy page.

**Architecture:** Introduce a read-only all-groups provider and a local active-group selector, derive the displayed group in Flutter instead of relying on a single core-selected group, then add pure search/locate helpers and wire them into `ProxiesOverviewPage`.

**Tech Stack:** Flutter, Riverpod, existing Hiddify proxy repository.

## Global Constraints

- Flutter-only; do not modify hiddify-core, Android, iOS, or database schema.
- Do not change proxy selection semantics.
- Search text is page-local and never persisted.
- Result tap switches the displayed group and scrolls/highlights the node, but does not select it.
- Automatic current-node location fires only once after the first non-empty displayed group snapshot.

---

### Task 1: Add All-Groups Provider and Search Helpers

**Files:**
- Create: `lib/features/proxy/model/proxy_search_result.dart`
- Create: `lib/features/proxy/domain/proxy_search.dart`
- Create: `lib/features/proxy/overview/all_proxies_overview_provider.dart`
- Create: `test/features/proxy/domain/proxy_search_test.dart`

**Interfaces:**
- Produces:
  - `class ProxySearchResult { String groupTag; String nodeTag; int delay; }`
  - `List<ProxySearchResult> searchProxyGroups(List<OutboundGroup> groups, String query)`
  - `String formatProxySearchDelay(int delay)`
  - `final allProxiesOverviewProvider = StreamProvider<List<OutboundGroup>>((ref) => ref.watch(proxyRepositoryProvider).watchActiveProxies().map(...));`

- [ ] **Step 1: Write failing search test**

Create `test/features/proxy/domain/proxy_search_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/domain/proxy_search.dart';
import 'package:hiddify/features/proxy/model/proxy_search_result.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

void main() {
  test('search matches node and group names case-insensitively', () {
    final groups = [
      OutboundGroup(tag: 'Auto', items: [OutboundInfo(tag: 'HK-01', urlTestDelay: 123)]),
      OutboundGroup(tag: 'Manual', items: [OutboundInfo(tag: 'US-02', urlTestDelay: 0)]),
    ];

    final result = searchProxyGroups(groups, 'hk');

    expect(result, hasLength(1));
    expect(result.single.groupTag, 'Auto');
    expect(result.single.nodeTag, 'HK-01');
  });

  test('delay formatting uses double dash for zero', () {
    expect(formatProxySearchDelay(0), '--');
    expect(formatProxySearchDelay(128), '128 ms');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
flutter test test/features/proxy/domain/proxy_search_test.dart
```

Expected: FAIL because `proxy_search.dart` does not exist.

- [ ] **Step 3: Implement model and search helper**

Create `lib/features/proxy/model/proxy_search_result.dart`:

```dart
class ProxySearchResult {
  const ProxySearchResult({
    required this.groupTag,
    required this.nodeTag,
    required this.delay,
  });

  final String groupTag;
  final String nodeTag;
  final int delay;
}
```

Create `lib/features/proxy/domain/proxy_search.dart`:

```dart
import 'package:hiddify/features/proxy/model/proxy_search_result.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

List<ProxySearchResult> searchProxyGroups(
  List<OutboundGroup> groups,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return const [];

  final results = <ProxySearchResult>[];
  for (final group in groups) {
    for (final item in group.items) {
      if (group.tag.toLowerCase().contains(normalized) ||
          item.tag.toLowerCase().contains(normalized)) {
        results.add(
          ProxySearchResult(
            groupTag: group.tag,
            nodeTag: item.tag,
            delay: item.urlTestDelay,
          ),
        );
      }
    }
  }

  results.sort((a, b) {
    final groupCompare = a.groupTag.compareTo(b.groupTag);
    if (groupCompare != 0) return groupCompare;
    return a.nodeTag.compareTo(b.nodeTag);
  });
  return results;
}

String formatProxySearchDelay(int delay) {
  return delay > 0 ? '$delay ms' : '--';
}
```

- [ ] **Step 4: Implement all-groups provider**

Create `lib/features/proxy/overview/all_proxies_overview_provider.dart`:

```dart
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final allProxiesOverviewProvider = StreamProvider<List<OutboundGroup>>((ref) {
  return ref.watch(proxyRepositoryProvider).watchActiveProxies().map(
        (event) => event.getOrElse((_) => const <OutboundGroup>[]),
      );
});
```

- [ ] **Step 5: Run tests**

Run:

```bash
flutter test test/features/proxy/domain/proxy_search_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/proxy/model/proxy_search_result.dart \
  lib/features/proxy/domain/proxy_search.dart \
  lib/features/proxy/overview/all_proxies_overview_provider.dart \
  test/features/proxy/domain/proxy_search_test.dart
git commit -m "feat: add proxy search helpers and all-groups provider"
```

---

### Task 2: Add Local Active Group Selection

**Files:**
- Create: `lib/features/proxy/notifier/active_proxy_group_notifier.dart`
- Create: `test/features/proxy/notifier/active_proxy_group_notifier_test.dart`
- Modify: `lib/features/proxy/overview/proxies_overview_notifier.dart`

**Interfaces:**
- Produces:
  - `final activeProxyGroupNotifierProvider = NotifierProvider<ActiveProxyGroupNotifier, String?>`
  - `class ActiveProxyGroupNotifier extends Notifier<String?>` with `build`, `select(String tag)`, and `setDefault(List<OutboundGroup> groups)`.
  - `ProxiesOverviewNotifier` now watches `allProxiesOverviewProvider` and derives the group selected by `activeProxyGroupNotifierProvider`.

- [ ] **Step 1: Write failing selection test**

Create `test/features/proxy/notifier/active_proxy_group_notifier_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/notifier/active_proxy_group_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('select changes active group and setDefault picks first', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(activeProxyGroupNotifierProvider.notifier);
    notifier.setDefault([
      OutboundGroup(tag: 'A'),
      OutboundGroup(tag: 'B'),
    ]);
    expect(notifier.state, 'A');
    notifier.select('B');
    expect(notifier.state, 'B');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
flutter test test/features/proxy/notifier/active_proxy_group_notifier_test.dart
```

Expected: FAIL because `active_proxy_group_notifier.dart` does not exist.

- [ ] **Step 3: Implement active group notifier**

Create `lib/features/proxy/notifier/active_proxy_group_notifier.dart`:

```dart
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_proxy_group_notifier.g.dart';

@riverpod
class ActiveProxyGroupNotifier extends _$ActiveProxyGroupNotifier {
  @override
  String? build() => null;

  void select(String tag) => state = tag;

  void setDefault(List<OutboundGroup> groups) {
    if (state == null || groups.any((group) => group.tag == state)) {
      state = groups.isEmpty ? null : groups.first.tag;
    }
  }
}
```

- [ ] **Step 4: Generate provider (or use a manual `NotifierProvider` if codegen is unavailable)**

Run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: generated `active_proxy_group_notifier.g.dart`. If the repository's local build_runner/slang cache is incompatible, a manual `NotifierProvider` with a plain `Notifier<String?>` class is acceptable; commit no generated file in that fallback.

- [ ] **Step 5: Run selection test**

Run:

```bash
flutter test test/features/proxy/notifier/active_proxy_group_notifier_test.dart
```

Expected: PASS.

- [ ] **Step 6: Update displayed group notifier**

In `ProxiesOverviewNotifier.build`, watch all groups and active selection instead of `watchProxies`:

```dart
final groups = ref.watch(allProxiesOverviewProvider).valueOrNull ?? const <OutboundGroup>[];
ref.read(activeProxyGroupNotifierProvider.notifier).setDefault(groups);
final selectedTag = ref.watch(activeProxyGroupNotifierProvider);
final selectedGroup = groups.where((group) => group.tag == selectedTag).firstOrNull;
```

Keep the existing blacklist filter and `_sortOutbounds` logic for the selected group. Return the filtered, sorted selected group.

- [ ] **Step 7: Verify analyzer**

Run:

```bash
flutter analyze lib/features/proxy
```

Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add lib/features/proxy/notifier/active_proxy_group_notifier.dart \
  lib/features/proxy/notifier/active_proxy_group_notifier.g.dart \
  lib/features/proxy/overview/proxies_overview_notifier.dart \
  test/features/proxy/notifier/active_proxy_group_notifier_test.dart
git commit -m "feat: add local active proxy group selection"
```

---

### Task 3: Integrate Search UI

**Files:**
- Modify: `lib/features/proxy/overview/proxies_overview_page.dart`
- Create: `lib/features/proxy/widget/proxy_search_overlay.dart`
- Test: no separate test file; existing widget smoke test can be extended in Task 4.

**Interfaces:**
- Consumes:
  - `allProxiesOverviewProvider`
  - `activeProxyGroupNotifierProvider`
  - `searchProxyGroups`
  - `formatProxySearchDelay`

- [ ] **Step 1: Create search overlay widget**

Create `lib/features/proxy/widget/proxy_search_overlay.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:hiddify/features/proxy/domain/proxy_search.dart';
import 'package:hiddify/features/proxy/model/proxy_search_result.dart';

class ProxySearchOverlay extends StatelessWidget {
  const ProxySearchOverlay({
    super.key,
    required this.results,
    required this.onSelected,
  });

  final List<ProxySearchResult> results;
  final ValueChanged<ProxySearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();
    return Material(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: results.length,
        itemBuilder: (context, index) {
          final result = results[index];
          return ListTile(
            title: Text(result.groupTag),
            subtitle: Text(
              '${result.nodeTag} - ${formatProxySearchDelay(result.delay)}',
            ),
            onTap: () => onSelected(result),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Add search field and results**

In `ProxiesOverviewPage`, add page-local `searchQuery` with `useState('')`. Render a `TextField` below the app bar and pass derived results into `ProxySearchOverlay`.

```dart
final groups = ref.watch(allProxiesOverviewProvider).valueOrNull ?? const [];
final results = searchProxyGroups(groups, searchQuery.value);
```

- [ ] **Step 3: Verify analyzer**

Run:

```bash
flutter analyze lib/features/proxy
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/proxy/widget/proxy_search_overlay.dart \
  lib/features/proxy/overview/proxies_overview_page.dart
git commit -m "feat: add proxy search overlay"
```

---

### Task 4: Wire Jump, Highlight, and Auto-Location

**Files:**
- Modify: `lib/features/proxy/overview/proxies_overview_page.dart`
- Modify: `lib/features/proxy/widget/proxy_tile.dart`

**Interfaces:**
- Consumes:
  - `activeProxyGroupNotifierProvider.select`
  - `ProxyTile.highlight`

- [ ] **Step 1: Add highlightable tile state**

In `ProxyTile`, add:

```dart
final bool highlight;
```

When `highlight` is true, render a temporary border or background color using an `AnimatedContainer`.

- [ ] **Step 2: Add auto-location**

In `ProxiesOverviewPage`, use a `ScrollController` and a `useState(false)` flag. After the first displayed group snapshot with a selected node, scroll once to that node and mark the flag true.

- [ ] **Step 3: Handle result tap**

```dart
void onSearchResultSelected(ProxySearchResult result) {
  ref.read(activeProxyGroupNotifierProvider.notifier).select(result.groupTag);
  searchQuery.value = '';
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _scrollToNode(result.nodeTag);
    _highlightedNode.value = result.nodeTag;
  });
}
```

- [ ] **Step 4: Verify analyzer**

Run:

```bash
flutter analyze lib/features/proxy
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/proxy/overview/proxies_overview_page.dart \
  lib/features/proxy/widget/proxy_tile.dart
git commit -m "feat: add proxy jump and auto-location"
```

---

### Task 5: Widget and Regression Tests

**Files:**
- Modify: `test/features/proxy/overview/proxies_overview_page_test.dart` or create a new focused test.
- Run regression: `test/drift/db/migration_test.dart`, `test/features/profile/data/profile_parser_test.dart`.

**Interfaces:**
- Consumes: `ProxySearchOverlay`, `ProxySearchResult`.

- [ ] **Step 1: Add search overlay widget test**

Create a widget test that pumps `ProxySearchOverlay` with two results, taps the second result, and verifies the callback receives that result.

- [ ] **Step 2: Run proxy tests**

Run:

```bash
flutter test test/features/proxy
```

Expected: all proxy tests pass.

- [ ] **Step 3: Run regression tests**

Run:

```bash
flutter test test/drift/db/migration_test.dart test/features/profile/data/profile_parser_test.dart
```

Expected: no regressions.

- [ ] **Step 4: Commit**

```bash
git add test/features/proxy
git commit -m "test: add proxy search widget tests"
```
