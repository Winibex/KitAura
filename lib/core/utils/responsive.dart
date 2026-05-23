import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';

class Responsive {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < AppSizes.mobile;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= AppSizes.mobile &&
          MediaQuery.of(context).size.width < AppSizes.tablet;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= AppSizes.tablet;
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context)) return desktop;
    if (Responsive.isTablet(context)) return tablet ?? desktop;
    return mobile;
  }
}