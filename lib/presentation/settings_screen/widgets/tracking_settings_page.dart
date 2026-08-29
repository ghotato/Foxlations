import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/tracking_provider.dart';
import '../../../core/tracking/tracker.dart';
import '../../../theme/app_theme.dart';
import '../../tracking/tracker_oauth_screen.dart';

class TrackingSettingsPage extends StatelessWidget {
  const TrackingSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tracking = context.watch<TrackingProvider>();
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: cs.onSurface, size: 20),
            onPressed: () => Navigator.pop(context)),
        title: Text('Tracking',
            style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
      ),
      body: ListView(
        padding: EdgeInsets.only(
            top: 8, bottom: 8 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _SectionHeader(title: 'Services'),
          for (final t in tracking.trackers) _TrackerTile(tracker: t),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Connect a tracking service to sync your reading progress. '
              'Once a manga is linked, progress updates automatically as you read.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 12, color: cs.outline, height: 1.5),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _TrackerTile extends StatelessWidget {
  final Tracker tracker;
  const _TrackerTile({required this.tracker});

  IconData get _icon {
    switch (tracker.id) {
      case 'anilist':
        return Icons.auto_graph_rounded;
      case 'kitsu':
        return Icons.pets_rounded;
      default:
        return Icons.track_changes_rounded;
    }
  }

  Future<void> _connect(BuildContext context) async {
    final tp = context.read<TrackingProvider>();
    if (tracker.authType == TrackerAuthType.credentials) {
      await _credentialsLogin(context, tp);
    } else {
      await _oauthLogin(context, tp);
    }
  }

  Future<void> _credentialsLogin(
      BuildContext context, TrackingProvider tp) async {
    final userCtl = TextEditingController();
    final passCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Log in to ${tracker.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: userCtl,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email or username'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: passCtl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Log in')),
        ],
      ),
    );
    if (ok != true) return;
    final success = await tp.connectWithCredentials(
        tracker.id, userCtl.text.trim(), passCtl.text);
    if (context.mounted) {
      AppTheme.showSnackBar(
          context,
          success
              ? 'Connected to ${tracker.name}'
              : 'Login failed — check your credentials');
    }
  }

  Future<void> _oauthLogin(BuildContext context, TrackingProvider tp) async {
    var cid = tp.clientId(tracker.id);
    if (cid.isEmpty) {
      final entered = await _promptClientId(context, tp);
      if (entered == null || entered.isEmpty) return;
      cid = entered;
    }
    final url = tp.authorizeUrl(tracker.id);
    if (url == null) {
      if (context.mounted) {
        AppTheme.showSnackBar(context, 'Set a client ID first');
      }
      return;
    }
    final captured = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => TrackerOAuthScreen(
          authorizeUrl: url,
          trackerName: tracker.name,
          usesCode: tracker.oauthUsesCode,
          redirectUri: tracker.oauthRedirect,
        ),
      ),
    );
    if (captured == null || captured.isEmpty) {
      // Manual token paste only helps token flows; a PKCE code can't be pasted
      // (it is single-use and tied to the in-flight verifier).
      if (!tracker.oauthUsesCode && context.mounted) {
        await _manualToken(context, tp);
      }
      return;
    }
    final ok = await tp.completeOAuth(tracker.id, captured);
    if (context.mounted) {
      AppTheme.showSnackBar(context,
          ok ? 'Connected to ${tracker.name}' : 'Could not complete sign-in');
    }
  }

  Future<String?> _promptClientId(
      BuildContext context, TrackingProvider tp) async {
    final ctl = TextEditingController(text: tp.clientId(tracker.id));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${tracker.name} client ID (advanced)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Optional. Foxlations already has a built-in ${tracker.name} client '
            'ID — just tap Connect. Only set this if you registered your own '
            '${tracker.name} developer app and want to use it instead.',
            style: GoogleFonts.manrope(fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Client ID'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return null;
    await tp.setClientId(tracker.id, ctl.text.trim());
    return ctl.text.trim();
  }

  Future<void> _manualToken(BuildContext context, TrackingProvider tp) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Paste access token'),
        content: TextField(
          controller: ctl,
          maxLines: 3,
          autocorrect: false,
          decoration: const InputDecoration(
              hintText: 'Paste the token shown after authorizing'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Connect')),
        ],
      ),
    );
    if (ok != true || ctl.text.trim().isEmpty) return;
    final connected = await tp.connectWithToken(tracker.id, ctl.text.trim());
    if (context.mounted) {
      AppTheme.showSnackBar(context,
          connected ? 'Connected to ${tracker.name}' : 'Could not verify token');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final connected = tracker.isAuthenticated;
    final color = Color(tracker.colorValue);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(_icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tracker.name,
                style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const SizedBox(height: 2),
            Text(
              connected
                  ? 'Connected${tracker.username != null ? ' as ${tracker.username}' : ''}'
                  : (tracker.authType == TrackerAuthType.oauth
                      ? 'Tap Connect to authorize'
                      : 'Sign in with your account'),
              style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: connected ? AppTheme.success : cs.outline),
            ),
          ]),
        ),
        if (!connected && tracker.authType == TrackerAuthType.oauth)
          IconButton(
            tooltip: 'Client ID',
            icon: Icon(Icons.key_rounded, size: 18, color: cs.outline),
            onPressed: () =>
                _promptClientId(context, context.read<TrackingProvider>()),
          ),
        GestureDetector(
          onTap: () => connected
              ? context.read<TrackingProvider>().disconnect(tracker.id)
              : _connect(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: connected
                  ? AppTheme.error.withAlpha(26)
                  : cs.primary.withAlpha(26),
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              border: Border.all(
                  color: connected ? AppTheme.error : cs.primary, width: 1),
            ),
            child: Text(connected ? 'Disconnect' : 'Connect',
                style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: connected ? AppTheme.error : cs.primary)),
          ),
        ),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(title.toUpperCase(),
          style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: cs.primary)),
    );
  }
}
