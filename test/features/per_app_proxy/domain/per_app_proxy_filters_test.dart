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
