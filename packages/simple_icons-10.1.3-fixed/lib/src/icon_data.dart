import 'package:flutter/material.dart';

/// Creates an [IconData] for a SimpleIcons icon
IconData makeSimpleIcon(int codePoint) => IconData(
  codePoint,
  fontFamily: 'SimpleIcons',
  fontPackage: 'simple_icons',
);
