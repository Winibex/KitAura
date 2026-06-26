import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kitaura/shared/services/connectivity_service.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  ConnectivityService.initialize();
  debugPaintSizeEnabled = false;


  // Enable Flutter timeline tracing for Chrome DevTools profiling.
  // SAFE to leave in — these flags only activate in profile/debug mode,
  // and only emit data when Chrome is recording.
  debugProfileBuildsEnabled = true;
  debugProfileBuildsEnabledUserWidgets = true;
  debugProfileLayoutsEnabled = true;
  debugProfilePaintsEnabled = true;


  runApp(
    const ProviderScope(
      child: KitAuraApp(),
    ),
  );
}