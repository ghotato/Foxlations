import 'package:flutter/material.dart';

/// Global navigator key so non-widget code (e.g. the extension HTTP bridge) can
/// present UI — used to show the interactive Cloudflare challenge screen.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Global messenger key so services with no BuildContext (e.g. the Cloudflare
/// solver running from the loopback FlareSolverr server) can surface toasts.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Shows a brief floating toast from anywhere in the app. [status] tints it:
/// null = neutral, true = success (green), false = failure (red). No-ops safely
/// when no UI is mounted yet.
void showGlobalToast(String message, {bool? status}) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) return;
  final bg = status == null
      ? const Color(0xFF2E2E44)
      : (status ? const Color(0xFF1B5E20) : const Color(0xFFB3261E));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      backgroundColor: bg,
    ));
}
