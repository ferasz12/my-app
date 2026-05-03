// lib/app/app_nav.dart
import 'package:flutter/material.dart';

class AppNav {
  AppNav._();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static Future<void> openDeeplink(String? deeplink) async {
    final nav = key.currentState;
    if (nav == null) return;

    final link = (deeplink ?? '').trim();
    if (link.isEmpty) return;

    // لو الرابط هو Route موجود عندك في main.dart routes
    // مثل: /home, /settings, /recipes ...
    try {
      nav.pushNamed(link);
      return;
    } catch (_) {
      // ignore
    }

    // FallBack
    nav.pushNamed('/home');
  }
}
