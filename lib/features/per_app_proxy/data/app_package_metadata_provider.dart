import 'package:hiddify/features/per_app_proxy/data/app_package_metadata_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final appPackageMetadataRepositoryProvider =
    Provider<AppPackageMetadataRepository>(
  (ref) => AppPackageMetadataRepository(),
);
