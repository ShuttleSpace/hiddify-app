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
