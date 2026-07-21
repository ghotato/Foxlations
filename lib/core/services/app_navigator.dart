import 'package:flutter/widgets.dart';

/// Global navigator key so non-widget code (e.g. the extension HTTP bridge) can
/// present UI — used to show the interactive Cloudflare challenge screen.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
