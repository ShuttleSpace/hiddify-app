import 'package:humanizer/humanizer.dart';

extension ByteFormatter on int {
  String size() => bytes().toString();

  static final _sizeOfFormat = InformationSizeFormat(permissibleValueUnits: {InformationUnit.gibibyte});

  String sizeGB() => _sizeOfFormat.format(bytes());

  String sizeOf(int total) => "${_sizeOfFormat.format(bytes())} / ${_sizeOfFormat.format(total.bytes())}";

  bool isInfinitSize() => bytes().terabytes.toDouble() > 10;

  static final _rateFormat = InformationRateFormat(permissibleRateUnits: {RateUnit.second});

  String speed() => _rateFormat.format(bytes().per(const Duration(seconds: 1)));

  String speedCompact() {
    final bytes = this;
    if (bytes <= 0) return '0';

    const units = ['K', 'M', 'G', 'T'];
    var value = bytes / 1000;
    var unitIndex = 0;
    while (value >= 1000 && unitIndex < units.length - 1) {
      value /= 1000;
      unitIndex++;
    }

    final text = value.toStringAsFixed(2);
    return '$text${units[unitIndex]}';
  }
}
