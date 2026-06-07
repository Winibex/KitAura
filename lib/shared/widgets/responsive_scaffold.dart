// lib/shared/widgets/responsive_scaffold.dart
//
// Drop-in replacement for Scaffold + AppTopBar + AppSidebar.
// Uses your existing Responsive class.

import 'package:flutter/material.dart';
import 'package:kitaura/shared/widgets/app_sidebar.dart';
import 'package:kitaura/shared/widgets/app_top_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

class ResponsiveScaffold extends StatelessWidget {
  final Widget child;
  final bool canBack;
  final String whereToGo;

  const ResponsiveScaffold({
    super.key,
    required this.child,
    this.canBack = false,
    this.whereToGo = '',
  });

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.lavenderBlush,
      drawer: mobile ? const Drawer(child: AppSidebar()) : null,
      body: Builder(builder: (ctx) {
        return Column(
          children: [
            AppTopBar(
              canBack: canBack,
              whereToGo: whereToGo,
              showMenuButton: mobile,
              onMenuTap: () => Scaffold.of(ctx).openDrawer(),
            ),
            Expanded(
              child: Row(
                children: [
                  if (!mobile) const AppSidebar(),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}