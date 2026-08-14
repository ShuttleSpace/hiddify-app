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
}
