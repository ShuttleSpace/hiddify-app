# Android Per-App Proxy Access Control Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the existing Android per-app proxy page with effective-state feedback, metadata filters, and visible-list batch selection while preserving current include/exclude persistence.

**Architecture:** Add a Flutter metadata repository backed by the existing Android `com.hiddify.app/platform` method channel, extend `AppPackageInfo` with display-only metadata, extract pure filter/summary helpers, and integrate them into `PerAppProxyPage`.

**Tech Stack:** Flutter, Riverpod, Drift, Android Kotlin platform channel, installed package metadata.

## Global Constraints

- Android-only UI and platform metadata; do not modify hiddify-core routing.
- Do not modify iOS.
- Do not add a database migration.
- Filter state is local to the page and is not persisted.
- Batch writes reuse `PerAppProxy.updatePkg`; do not bypass flag semantics.
- Existing import/export, auto-selection, and include/exclude behavior must remain unchanged.

---

### Task 1: Expose Android Package Metadata

**Files:**
- Modify: `android/app/src/main/kotlin/com/hiddify/hiddify/PlatformSettingsHandler.kt`
- Test: run Android debug compilation after change.

**Interfaces:**
- Produces native method `get_installed_packages` returning a JSON array with fields:
  - `package-name: String`
  - `name: String`
  - `is-system-app: Boolean`
  - `has-internet-permission: Boolean`
- Produces native method `get_package_icon` unchanged, already returns a PNG base64 string for `packageName`.

- [ ] **Step 1: Update `AppItem`**

Open `PlatformSettingsHandler.kt` and change the data class:

```kotlin
data class AppItem(
    @SerializedName("package-name") val packageName: String,
    @SerializedName("name") val name: String,
    @SerializedName("is-system-app") val isSystemApp: Boolean,
    @SerializedName("has-internet-permission") val hasInternetPermission: Boolean
)
```

- [ ] **Step 2: Update `GetInstalledPackages`**

Replace the package filtering block with:

```kotlin
installedPackages.forEach {
    if (it.packageName != Application.application.packageName) {
        list.add(
            AppItem(
                it.packageName,
                it.applicationInfo?.loadLabel(packageManager).toString(),
                (it.applicationInfo?.flags?.and(ApplicationInfo.FLAG_SYSTEM) == 1),
                it.requestedPermissions?.contains(Manifest.permission.INTERNET) == true
            )
        )
    }
}
```

- [ ] **Step 3: Verify Kotlin compilation**

Run:

```bash
./gradlew :app:compileDebugKotlin
```

Expected: build succeeds with no unresolved reference.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/com/hiddify/hiddify/PlatformSettingsHandler.kt
git commit -m "feat: expose android app internet permission metadata"
```

---

### Task 2: Add Flutter Package Metadata Repository

**Files:**
- Modify: `lib/features/per_app_proxy/model/app_package_info.dart`
- Create: `lib/features/per_app_proxy/data/app_package_metadata_repository.dart`
- Create: `lib/features/per_app_proxy/data/app_package_metadata_provider.dart`

**Interfaces:**
- Consumes: native methods from Task 1.
- Produces:
  - `class AppPackageInfo { String packageName; String name; Uint8List? icon; bool isSystemApp; bool hasInternetPermission; }`
  - `class AppPackageMetadataRepository { Future<List<AppPackageInfo>> getInstalledApps(); Future<Uint8List?> getIcon(String packageName); }`
  - `final appPackageMetadataRepositoryProvider = Provider<AppPackageMetadataRepository>((ref) => AppPackageMetadataRepository());`

- [ ] **Step 1: Extend model**

Modify `app_package_info.dart`:

```dart
import 'dart:typed_data';

class AppPackageInfo {
  const AppPackageInfo({
    required this.packageName,
    required this.name,
    required this.icon,
    this.isSystemApp = false,
    this.hasInternetPermission = false,
  });

  final String packageName;
  final String name;
  final Uint8List? icon;
  final bool isSystemApp;
  final bool hasInternetPermission;
}
```

- [ ] **Step 2: Write repository**

Create `app_package_metadata_repository.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';

class AppPackageMetadataRepository {
  static const _channel = MethodChannel('com.hiddify.app/platform');

  Future<List<AppPackageInfo>> getInstalledApps() async {
    final raw = await _channel.invokeMethod<String>('get_installed_packages');
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    final apps = <AppPackageInfo>[];
    for (final item in decoded) {
      final map = item as Map<dynamic, dynamic>;
      apps.add(
        AppPackageInfo(
          packageName: map['package-name'] as String,
          name: map['name'] as String,
          icon: null,
          isSystemApp: map['is-system-app'] as bool? ?? false,
          hasInternetPermission: map['has-internet-permission'] as bool? ?? false,
        ),
      );
    }
    return apps;
  }

  Future<Uint8List?> getIcon(String packageName) async {
    final base64 = await _channel.invokeMethod<String>(
      'get_package_icon',
      {'packageName': packageName},
    );
    return base64 == null ? null : base64Decode(base64);
  }
}
```

- [ ] **Step 3: Write provider**

Create `app_package_metadata_provider.dart`:

```dart
import 'package:hiddify/features/per_app_proxy/data/app_package_metadata_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final appPackageMetadataRepositoryProvider =
    Provider<AppPackageMetadataRepository>(
  (ref) => AppPackageMetadataRepository(),
);
```

- [ ] **Step 4: Verify analyzer**

Run:

```bash
flutter analyze lib/features/per_app_proxy
```

Expected: no errors in the new files.

- [ ] **Step 5: Commit**

```bash
git add lib/features/per_app_proxy/model/app_package_info.dart \
  lib/features/per_app_proxy/data/app_package_metadata_repository.dart \
  lib/features/per_app_proxy/data/app_package_metadata_provider.dart
git commit -m "feat: add android app metadata repository"
```

---

### Task 3: Add Pure Filter, Summary, and Batch Selection Helpers

**Files:**
- Create: `lib/features/per_app_proxy/domain/per_app_proxy_filters.dart`
- Create: `lib/features/per_app_proxy/domain/per_app_proxy_summary.dart`
- Create: `test/features/per_app_proxy/domain/per_app_proxy_filters_test.dart`
- Create: `test/features/per_app_proxy/domain/per_app_proxy_summary_test.dart`

**Interfaces:**
- Consumes: `AppPackageInfo`, `PkgFlag`, `AppProxyMode`.
- Produces:
  - `enum AppPackageFilter { all, system, nonSystem, internet, noInternet }`
  - `bool matchesAppPackageFilter(AppPackageInfo app, AppPackageFilter filter)`
  - `List<AppPackageInfo> filterAndSearchApps(List<AppPackageInfo> apps, AppPackageFilter filter, String query)`
  - `class PerAppProxySummary { int active; int userSelected; int autoSelected; int forceDeselected; }`
  - `PerAppProxySummary computePerAppProxySummary(Map<String, int> flags)`
  - `Set<String> packagesToToggle(List<AppPackageInfo> visibleApps, Map<String, int> flags, bool select)`

- [ ] **Step 1: Write failing filter tests**

Create `test/features/per_app_proxy/domain/per_app_proxy_filters_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/per_app_proxy/domain/per_app_proxy_filters.dart';
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';

void main() {
  const systemInternet = AppPackageInfo(
    packageName: 'system.internet',
    name: 'System Internet',
    icon: null,
    isSystemApp: true,
    hasInternetPermission: true,
  );
  const userNoInternet = AppPackageInfo(
    packageName: 'user.nointernet',
    name: 'User No Internet',
    icon: null,
    isSystemApp: false,
    hasInternetPermission: false,
  );

  test('filters system and internet apps', () {
    expect(
      filterAndSearchApps(
        const [systemInternet, userNoInternet],
        AppPackageFilter.internet,
        '',
      ),
      [systemInternet],
    );
  });

  test('applies search after filter', () {
    expect(
      filterAndSearchApps(
        const [systemInternet, userNoInternet],
        AppPackageFilter.all,
        'user',
      ),
      [userNoInternet],
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
flutter test test/features/per_app_proxy/domain/per_app_proxy_filters_test.dart
```

Expected: FAIL because `per_app_proxy_filters.dart` does not exist.

- [ ] **Step 3: Implement filter helper**

Create `lib/features/per_app_proxy/domain/per_app_proxy_filters.dart`:

```dart
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';

enum AppPackageFilter { all, system, nonSystem, internet, noInternet }

bool matchesAppPackageFilter(AppPackageInfo app, AppPackageFilter filter) {
  return switch (filter) {
    AppPackageFilter.all => true,
    AppPackageFilter.system => app.isSystemApp,
    AppPackageFilter.nonSystem => !app.isSystemApp,
    AppPackageFilter.internet => app.hasInternetPermission,
    AppPackageFilter.noInternet => !app.hasInternetPermission,
  };
}

List<AppPackageInfo> filterAndSearchApps(
  List<AppPackageInfo> apps,
  AppPackageFilter filter,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  return apps.where((app) {
    return matchesAppPackageFilter(app, filter) &&
        (normalizedQuery.isEmpty ||
            app.name.toLowerCase().contains(normalizedQuery));
  }).toList();
}
```

- [ ] **Step 4: Run filter tests**

Run:

```bash
flutter test test/features/per_app_proxy/domain/per_app_proxy_filters_test.dart
```

Expected: PASS.

- [ ] **Step 5: Write failing summary tests**

Create `test/features/per_app_proxy/domain/per_app_proxy_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/per_app_proxy/domain/per_app_proxy_summary.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';

void main() {
  test('counts active, user, auto, and force deselected packages', () {
    final summary = computePerAppProxySummary({
      'user': PkgFlag.userSelection.add(0),
      'auto': PkgFlag.autoSelection.add(0),
      'forced': PkgFlag.forceDeselection.add(0),
    });

    expect(summary.userSelected, 1);
    expect(summary.autoSelected, 1);
    expect(summary.forceDeselected, 1);
    expect(summary.active, 2);
  });
}
```

- [ ] **Step 6: Run summary tests to verify they fail**

Run:

```bash
flutter test test/features/per_app_proxy/domain/per_app_proxy_summary_test.dart
```

Expected: FAIL because `per_app_proxy_summary.dart` does not exist.

- [ ] **Step 7: Implement summary helper**

Create `lib/features/per_app_proxy/domain/per_app_proxy_summary.dart`:

```dart
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';

class PerAppProxySummary {
  const PerAppProxySummary({
    required this.active,
    required this.userSelected,
    required this.autoSelected,
    required this.forceDeselected,
  });

  final int active;
  final int userSelected;
  final int autoSelected;
  final int forceDeselected;
}

PerAppProxySummary computePerAppProxySummary(Map<String, int> flags) {
  var active = 0;
  var userSelected = 0;
  var autoSelected = 0;
  var forceDeselected = 0;

  for (final flag in flags.values) {
    if (PkgFlag.checkboxValue(flag) != false) active += 1;
    if (PkgFlag.userSelection.check(flag)) userSelected += 1;
    if (PkgFlag.autoSelection.check(flag) &&
        !PkgFlag.forceDeselection.check(flag)) {
      autoSelected += 1;
    }
    if (PkgFlag.forceDeselection.check(flag)) forceDeselected += 1;
  }

  return PerAppProxySummary(
    active: active,
    userSelected: userSelected,
    autoSelected: autoSelected,
    forceDeselected: forceDeselected,
  );
}
```

- [ ] **Step 8: Run summary tests**

Run:

```bash
flutter test test/features/per_app_proxy/domain/per_app_proxy_summary_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/features/per_app_proxy/domain \
  test/features/per_app_proxy/domain
git commit -m "feat: add per-app proxy filter and summary helpers"
```

---

### Task 4: Integrate Filters and Summary Into the Page

**Files:**
- Modify: `lib/features/per_app_proxy/overview/per_app_proxy_page.dart`
- Create: `lib/features/per_app_proxy/widget/per_app_proxy_summary_view.dart`

**Interfaces:**
- Consumes:
  - `appPackageMetadataRepositoryProvider`
  - `PerAppProxyProvider(AppProxyMode?)`
  - `AppPackageFilter`
  - `filterAndSearchApps`
  - `computePerAppProxySummary`

- [ ] **Step 1: Replace `InstalledApps` metadata calls**

Remove `package:installed_apps/index.dart` import. Replace `getApps` with:

```dart
Future<List<AppPackageInfo>> getApps(WidgetRef ref) async {
  if (!PlatformUtils.isAndroid) return const [];
  final repo = ref.read(appPackageMetadataRepositoryProvider);
  final apps = await repo.getInstalledApps();
  return apps
      .map(
        (app) => app.icon == null
            ? app
            : AppPackageInfo(
                packageName: app.packageName,
                name: app.name,
                icon: app.icon,
                isSystemApp: app.isSystemApp,
                hasInternetPermission: app.hasInternetPermission,
              ),
      )
      .toList();
}
```

Icons are intentionally loaded lazily by the existing tile widget. The metadata repository initially returns `icon: null`.

Update the page's app-list future to:

```dart
final asyncApps = useFuture(useMemoized(() => getApps(ref)));
```

Delete the old `asyncAppsHideSys` future and `hideSystemApps` state.

- [ ] **Step 2: Add filter state**

Inside `build`, add:

```dart
final filter = useState(AppPackageFilter.all);
```

Replace `displayedApps` with:

```dart
final displayedApps = useMemoized<AsyncValue<List<AppPackageInfo>>>(
  () {
    if (!(selectedApps.hasValue &&
        selectedApps is AsyncData &&
        asyncApps.hasData &&
        asyncApps.connectionState == ConnectionState.done)) {
      return const AsyncValue.loading();
    }
    final appsList = filterAndSearchApps(
      asyncApps.requireData,
      filter.value,
      searchQuery.value,
    );
    appsList.sort((a, b) {
      final priorityA = _getPriority(a, selectedApps.requireValue);
      final priorityB = _getPriority(b, selectedApps.requireValue);
      return priorityA.compareTo(priorityB);
    });
    return AsyncValue.data(appsList);
  },
  [
    asyncApps.connectionState == ConnectionState.done,
    selectedApps.hasValue,
    searchQuery.value,
    filter.value,
    sortListener.value,
  ],
);
```

Remove the old `hideSystemApps` and `asyncAppsHideSys` state, because system filtering is now handled by `AppPackageFilter`.

- [ ] **Step 3: Add filter chips**

Insert a horizontal `SingleChildScrollView` below the mode selector and above the app list:

```dart
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  child: Row(
    children: [
      for (final item in AppPackageFilter.values)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Text(item.name),
            selected: filter.value == item,
            onSelected: (_) => filter.value = item,
          ),
        ),
    ],
  ),
)
```

- [ ] **Step 4: Create summary view widget**

Create `lib/features/per_app_proxy/widget/per_app_proxy_summary_view.dart`:

```dart
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
```

- [ ] **Step 4b: Render summary view**

Before the list, insert:

```dart
PerAppProxySummaryView(
  summary: computePerAppProxySummary(
    selectedApps.valueOrNull ?? const {},
  ),
)
```

- [ ] **Step 5: Verify analyzer**

Run:

```bash
flutter analyze lib/features/per_app_proxy
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/per_app_proxy/overview/per_app_proxy_page.dart
git commit -m "feat: integrate per-app proxy filters and summary"
```

---

### Task 5: Add Visible-List Batch Selection

**Files:**
- Modify: `lib/features/per_app_proxy/overview/per_app_proxy_page.dart`
- Create: `test/features/per_app_proxy/domain/per_app_proxy_batch_test.dart`

**Interfaces:**
- Consumes: `packagesToToggle` from Task 3, `PerAppProxyProvider(mode)`.
- Produces:
  - `Future<void> selectVisibleApps(WidgetRef ref, AppProxyMode mode, List<AppPackageInfo> visibleApps, Map<String, int> flags, bool select)`

- [ ] **Step 1: Add batch toggle helper to domain**

Append to `per_app_proxy_filters.dart`:

```dart
Set<String> packagesToToggle(
  List<AppPackageInfo> visibleApps,
  Map<String, int> flags,
  bool select,
) {
  final result = <String>{};
  for (final app in visibleApps) {
    final flag = flags[app.packageName];
    final current = PkgFlag.checkboxValue(flag ?? 0);
    if (select && current != true) result.add(app.packageName);
    if (!select && current != false) result.add(app.packageName);
  }
  return result;
}
```

- [ ] **Step 2: Write failing batch test**

Create `test/features/per_app_proxy/domain/per_app_proxy_batch_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/per_app_proxy/domain/per_app_proxy_filters.dart';
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';

void main() {
  const appA = AppPackageInfo(
    packageName: 'a',
    name: 'A',
    icon: null,
    hasInternetPermission: true,
  );
  const appB = AppPackageInfo(
    packageName: 'b',
    name: 'B',
    icon: null,
    hasInternetPermission: true,
  );

  test('select all visible targets only unselected visible packages', () {
    final toggles = packagesToToggle(
      const [appA, appB],
      {
        'a': PkgFlag.userSelection.add(0),
      },
      true,
    );
    expect(toggles, {'b'});
  });
}
```

- [ ] **Step 3: Run batch test to verify it fails**

Run:

```bash
flutter test test/features/per_app_proxy/domain/per_app_proxy_batch_test.dart
```

Expected: FAIL because `packagesToToggle` is not defined.

- [ ] **Step 4: Run test after helper exists**

Run:

```bash
flutter test test/features/per_app_proxy/domain/per_app_proxy_batch_test.dart
```

Expected: PASS.

- [ ] **Step 5: Add select-all and deselect-all actions**

Add two buttons near the filter chips:

```dart
TextButton.icon(
  onPressed: () async {
    final toggles = packagesToToggle(
      displayedApps.valueOrNull ?? const [],
      selectedApps.valueOrNull ?? const {},
      true,
    );
    for (final packageName in toggles) {
      await ref.read(PerAppProxyProvider(mode).notifier).updatePkg(packageName);
    }
  },
  icon: const Icon(Icons.select_all_rounded),
  label: const Text('Select all'),
),
TextButton.icon(
  onPressed: () async {
    final toggles = packagesToToggle(
      displayedApps.valueOrNull ?? const [],
      selectedApps.valueOrNull ?? const {},
      false,
    );
    for (final packageName in toggles) {
      await ref.read(PerAppProxyProvider(mode).notifier).updatePkg(packageName);
    }
  },
  icon: const Icon(Icons.deselect_rounded),
  label: const Text('Deselect all'),
)
```

- [ ] **Step 6: Verify analyzer**

Run:

```bash
flutter analyze lib/features/per_app_proxy
```

Expected: no errors.

- [ ] **Step 7: Run full per-app proxy tests**

Run:

```bash
flutter test test/features/per_app_proxy
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/features/per_app_proxy test/features/per_app_proxy
git commit -m "feat: add visible-list batch selection for per-app proxy"
```

---

### Task 6: Widget Test and Regression Pass

**Files:**
- Create: `test/features/per_app_proxy/per_app_proxy_page_test.dart`
- Modify: no production code unless a test exposes a bug.

**Interfaces:**
- Consumes: `PerAppProxySummaryView`, `PerAppProxySummary`.

- [ ] **Step 1: Write widget smoke test**

Create `test/features/per_app_proxy/per_app_proxy_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/per_app_proxy/domain/per_app_proxy_summary.dart';
import 'package:hiddify/features/per_app_proxy/widget/per_app_proxy_summary_view.dart';

void main() {
  testWidgets('summary view renders counts', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PerAppProxySummaryView(
            summary: PerAppProxySummary(
              active: 12,
              userSelected: 10,
              autoSelected: 2,
              forceDeselected: 1,
            ),
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
```

- [ ] **Step 2: Run widget test**

Run:

```bash
flutter test test/features/per_app_proxy/per_app_proxy_page_test.dart
```

Expected: PASS or fail with an explicit missing-provider error that is fixed by adding the required overrides.

- [ ] **Step 3: Run existing related tests**

Run:

```bash
flutter test test/drift/db/migration_test.dart test/features/profile/data/profile_parser_test.dart
```

Expected: no regressions.

- [ ] **Step 4: Commit**

```bash
git add test/features/per_app_proxy/per_app_proxy_page_test.dart
git commit -m "test: add per-app proxy page widget test"
```
