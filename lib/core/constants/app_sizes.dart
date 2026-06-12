import 'package:flutter/material.dart';

import '../utils/responsive.dart';

class AppSizes {
  AppSizes._();

  // SPACING
  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 16.0;
  static const double lg   = 24.0;
  static const double xl   = 32.0;
  static const double xxl  = 48.0;

  // RADIUS
  static const double radiusSm  = 8.0;
  static const double radiusMd  = 12.0;
  static const double radiusLg  = 16.0;
  static const double radiusXl  = 24.0;
  static const double radiusFull = 999.0;

  // LAYOUT
  static const double navbarHeight  = 64.0;
  static const double sidebarWidth  = 240.0;

  // BREAKPOINTS
  static const double mobile  = 768.0;
  static const double tablet  = 1200.0;

  static double headingLg(BuildContext context) =>
      Responsive.isMobile(context) ? 20 : 26;

  static double headingMd(BuildContext context) =>
      Responsive.isMobile(context) ? 16 : 20;

  static double headingSm(BuildContext context) =>
      Responsive.isMobile(context) ? 14 : 16;

  static double body(BuildContext context) =>
      Responsive.isMobile(context) ? 12 : 14;

  static double caption(BuildContext context) =>
      Responsive.isMobile(context) ? 10 : 12;

  static double statValue(BuildContext context) =>
      Responsive.isMobile(context) ? 20 : 28;

  // RESPONSIVE PADDING
  static double pagePadding(BuildContext context) =>
      Responsive.isMobile(context) ? 16 : 32;

  static double cardPadding(BuildContext context) =>
      Responsive.isMobile(context) ? 12 : 20;

  // RESPONSIVE GRID
  static int statColumns(BuildContext context) =>
      Responsive.isMobile(context) ? 2 : Responsive.isTablet(context) ? 3 : 4;

  static double statAspectRatio(BuildContext context) =>
      Responsive.isMobile(context) ? 1.4 : 1.6;

  static double icons(BuildContext context) =>
      Responsive.isMobile(context) ? 18 : 28;

  static double coverLetterPrimaryButtonWidth(BuildContext context) =>
      Responsive.isMobile(context) ? 180 : 200;

  static double coverLetterSecondaryButtonWidth(BuildContext context) =>
      Responsive.isMobile(context) ? 150 : 170;

  static double proposalPrimaryButtonWidth(BuildContext context) =>
      Responsive.isMobile(context) ? 180 : 200;

  static double proposalSecondaryButtonWidth(BuildContext context) =>
      Responsive.isMobile(context) ? 150 : 170;

  static int docGridColumns(BuildContext context, double maxWidth) {
    if (maxWidth < 400) return 2;
    if (maxWidth < 700) return 2;
    if (maxWidth < 1000) return 3;
    return 4;
  }
}