import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kitaura/shared/services/connectivity_service.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:web/web.dart' as web;

// Params the app itself uses. Everything else is stripped.
const _allowedQueryParams = <String>{
  // Firebase Auth email actions
  'mode',
  'oobCode',
  'apiKey',
  'continueUrl',
  'lang',
  // Add app-specific params here as you add features
};

void _cleanTrackingParams() {
  try {
    final rawHref = web.window.location.href;
    final url = Uri.tryParse(rawHref);
    if (url == null || url.host.isEmpty) return;

    // Use queryParametersAll to preserve repeated keys.
    final rawQuery = url.queryParametersAll;
    final cleanedQuery = <String, List<String>>{};
    for (final entry in rawQuery.entries) {
      if (_allowedQueryParams.contains(entry.key)) {
        cleanedQuery[entry.key] = entry.value;
      }
    }

    // Normalize path: collapse double slashes, strip trailing slash (except root).
    var path = url.path.replaceAll(RegExp(r'/+'), '/');
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    // Preserve fragment.
    final fragment = url.fragment.isEmpty ? null : url.fragment;

    // Only rewrite if something actually changed.
    final queryChanged =
        cleanedQuery.length != rawQuery.length ||
            !cleanedQuery.entries.every((e) =>
            rawQuery[e.key]?.join(',') == e.value.join(','));
    final pathChanged = path != url.path;
    if (!queryChanged && !pathChanged) return;

    final cleanUri = url.replace(
      path: path,
      queryParameters: cleanedQuery.isEmpty ? null : cleanedQuery,
      fragment: fragment,
    );

    web.window.history.replaceState(null, '', cleanUri.toString());
  } catch (_) {
    // Never let URL normalization crash app startup.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseAppCheck.instance.activate(
    providerWeb: ReCaptchaEnterpriseProvider('6LdEkUktAAAAADnsEQSwXC3JYHwl7D3unJ0VayyR'),
  );

  ConnectivityService.initialize();
  debugPaintSizeEnabled = false;

  _cleanTrackingParams();

  runApp(
    const ProviderScope(
      child: KitAuraApp(),
    ),
  );
}