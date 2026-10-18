import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/per_app_proxy/domain/per_app_proxy_filters.dart';
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';

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

  test('packagesToToggle targets only visible packages', () {
    const visibleUnselected = AppPackageInfo(
      packageName: 'visible.unselected',
      name: 'Visible Unselected',
      icon: null,
      hasInternetPermission: true,
    );
    const visibleAuto = AppPackageInfo(
      packageName: 'visible.auto',
      name: 'Visible Auto',
      icon: null,
      hasInternetPermission: true,
    );
    const hiddenSelected = AppPackageInfo(
      packageName: 'hidden.selected',
      name: 'Hidden Selected',
      icon: null,
      hasInternetPermission: true,
    );

    final toggles = packagesToToggle(
      const [visibleUnselected, visibleAuto],
      {
        'visible.unselected': 0,
        'visible.auto': PkgFlag.autoSelection.add(0),
        'hidden.selected': PkgFlag.userSelection.add(0),
      },
      true,
    );

    expect(toggles, {'visible.unselected', 'visible.auto'});
  });

  test('packagesToToggle deselect omits absent and zero flags', () {
    const visibleAbsent = AppPackageInfo(
      packageName: 'visible.absent',
      name: 'Visible Absent',
      icon: null,
      hasInternetPermission: true,
    );
    const visibleZero = AppPackageInfo(
      packageName: 'visible.zero',
      name: 'Visible Zero',
      icon: null,
      hasInternetPermission: true,
    );
    const visibleSelected = AppPackageInfo(
      packageName: 'visible.selected',
      name: 'Visible Selected',
      icon: null,
      hasInternetPermission: true,
    );
    const visibleAuto = AppPackageInfo(
      packageName: 'visible.auto',
      name: 'Visible Auto',
      icon: null,
      hasInternetPermission: true,
    );

    final toggles = packagesToToggle(
      const [visibleAbsent, visibleZero, visibleSelected, visibleAuto],
      {
        'visible.zero': 0,
        'visible.selected': PkgFlag.userSelection.add(0),
        'visible.auto': PkgFlag.autoSelection.add(0),
      },
      false,
    );

    expect(toggles, {'visible.selected', 'visible.auto'});
  });
}
