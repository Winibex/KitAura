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

  /// Call once in main.dart before runApp
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Listen to browser online/offline events
    web.window.addEventListener('online', _onOnline.toJS);
    web.window.addEventListener('offline', _onOffline.toJS);

    // Set initial state from browser
    _isOnline = web.window.navigator.onLine;

    // Start polling for REAL connectivity (not just WiFi connected)
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => checkConnectivity());

    // Initial check
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
    try {
      // Use a lightweight endpoint that returns fast
      final controller = web.AbortController();
      final signal = controller.signal;

      // 5 second timeout
      final timer = Timer(const Duration(seconds: 5), () => controller.abort());

      await web.window.fetch(
        'https://www.gstatic.com/generate_204'.toJS,
        web.RequestInit(
          method: 'HEAD',
          signal: signal,
          mode: 'no-cors',
        ),
      ).toDart;

      timer.cancel();
      _updateStatus(true);
      return true;
    } catch (e) {
      _updateStatus(false);
      return false;
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
    _controller.close();
  }
}