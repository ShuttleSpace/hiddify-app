import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/per_app_proxy/domain/per_app_proxy_filters.dart';
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';

void main() {
  const appA = AppPackageInfo(packageName: 'a', name: 'A', icon: null, hasInternetPermission: true);
  const appB = AppPackageInfo(packageName: 'b', name: 'B', icon: null, hasInternetPermission: true);

  test('select all visible targets only unselected visible packages', () {
    final toggles = packagesToToggle(const [appA, appB], {'a': PkgFlag.userSelection.add(0)}, true);
    expect(toggles, {'b'});
  });

  test('needsSecondSelectUpdate detects force deselected packages', () {
    expect(needsSecondSelectUpdate(PkgFlag.autoSelection.add(PkgFlag.forceDeselection.add(0))), isTrue);
    expect(needsSecondSelectUpdate(null), isFalse);
  });

  test('runVisibleAppBatch continues after failures and retries force deselected packages', () async {
    final called = <String>[];
    Future<void> updatePkg(String packageName) async {
      called.add(packageName);
      if (packageName == 'fail') throw Exception('fail');
    }

    final failed = await runVisibleAppBatch(
      toggles: const ['fail', 'forced', 'ok'],
      flags: {'forced': PkgFlag.forceDeselection.add(0)},
      select: true,
      updatePkg: updatePkg,
    );

    expect(failed, ['fail']);
    expect(called, ['fail', 'forced', 'forced', 'ok']);
  });
}
