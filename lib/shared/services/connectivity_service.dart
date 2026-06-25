// lib/shared/services/connectivity_service.dart
//
// Checks REAL internet access (not just connected to WiFi/access point).
// Uses periodic HEAD requests to a reliable endpoint.
// Provides a stream for the UI to react to connectivity changes.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

class ConnectivityService {
  ConnectivityService._();

  static bool _isOnline = true;
  static bool get isOnline => _isOnline;

  static final StreamController<bool> _controller = StreamController<bool>.broadcast();
  static Stream<bool> get onConnectivityChanged => _controller.stream;

  static Timer? _pollTimer;
  static bool _initialized = false;

  static JSFunction? _onOnlineJs;
  static JSFunction? _onOfflineJs;

  /// Call once in main.dart before runApp
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Cache the JS wrappers so removeEventListener can use the SAME reference.
    _onOnlineJs = _onOnline.toJS;
    _onOfflineJs = _onOffline.toJS;
    web.window.addEventListener('online', _onOnlineJs);
    web.window.addEventListener('offline', _onOfflineJs);

    _isOnline = web.window.navigator.onLine;
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => checkConnectivity());
    checkConnectivity();
  }

  static void _onOnline(web.Event event) {
    checkConnectivity(); // Verify with actual request
  }

  static void _onOffline(web.Event event) {
    _updateStatus(false);
  }

  /// Performs an actual network request to verify internet access.
  /// Returns true if internet is reachable.
  static Future<bool> checkConnectivity() async {
    final controller = web.AbortController();
    final signal = controller.signal;
    final timer = Timer(const Duration(seconds: 5), () => controller.abort());

    try {
      await web.window.fetch(
        'https://www.gstatic.com/generate_204'.toJS,
        web.RequestInit(
          method: 'HEAD',
          signal: signal,
          mode: 'no-cors',
        ),
      ).toDart;
      _updateStatus(true);
      return true;
    } catch (e) {
      _updateStatus(false);
      return false;
    } finally {
      timer.cancel();                                // ← ALWAYS cancels now
    }
  }

  static void _updateStatus(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      _controller.add(online);
      debugPrint('🌐 Connectivity changed: ${online ? "ONLINE" : "OFFLINE"}');
    }
  }

  static void dispose() {
    _pollTimer?.cancel();
    if (_onOnlineJs != null) {
      web.window.removeEventListener('online', _onOnlineJs);
      _onOnlineJs = null;
    }
    if (_onOfflineJs != null) {
      web.window.removeEventListener('offline', _onOfflineJs);
      _onOfflineJs = null;
    }
    _controller.close();
    _initialized = false;
  }
}