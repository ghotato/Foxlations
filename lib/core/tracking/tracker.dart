import 'tracker_models.dart';

/// How a tracker authenticates.
enum TrackerAuthType {
  /// OAuth — open [Tracker.authorizeUrl] in a browser/WebView, then hand the
  /// resulting access token back via [Tracker.authenticateWithToken].
  oauth,

  /// Username + password (password grant) via [Tracker.authenticateWithCredentials].
  credentials,
}

/// A tracking service (AniList, Kitsu, …). Implementations own their auth,
/// their catalog search, and pushing progress. Session state is opaque JSON
/// that the [TrackingService] persists and restores.
abstract class Tracker {
  String get id; // stable slug, e.g. 'anilist'
  String get name; // display name
  int get colorValue; // brand color (ARGB int)
  TrackerAuthType get authType;

  bool get isAuthenticated;
  String? get username;

  /// Serialize/restore session (tokens, username) for persistence.
  Map<String, dynamic> exportSession();
  void restoreSession(Map<String, dynamic> data);
  void logout();

  // ── auth (implement the one matching [authType]) ──

  /// OAuth: the URL to open for the user to authorize. [clientId] is the
  /// user-supplied / built-in client id.
  String authorizeUrl(String clientId) =>
      throw UnsupportedError('$id does not use OAuth');

  /// OAuth: true if the redirect returns an authorization **code** to exchange
  /// (MAL, PKCE); false if it returns the access **token** directly (AniList,
  /// implicit grant). Drives how the WebView captures the result.
  bool get oauthUsesCode => false;

  /// OAuth: the redirect URI the WebView watches for (only meaningful for
  /// code-based flows; token flows read the fragment on the provider's page).
  String get oauthRedirect => '';

  /// OAuth (token/implicit): finish login with the intercepted access token.
  Future<bool> authenticateWithToken(String token) =>
      throw UnsupportedError('$id does not use token auth');

  /// OAuth (code/PKCE): finish login by exchanging the intercepted auth code.
  Future<bool> authenticateWithCode(String code) =>
      throw UnsupportedError('$id does not use code auth');

  /// Credentials: log in with username + password.
  Future<bool> authenticateWithCredentials(String username, String password) =>
      throw UnsupportedError('$id does not use credential auth');

  // ── operations (require [isAuthenticated] for writes) ──

  /// Search the tracker's catalog. Works without auth on most services.
  Future<List<TrackSearchResult>> search(String query);

  /// Current state of [mediaId] in the user's list, or null if not added yet.
  Future<TrackRecord?> refresh(String mediaId);

  /// Create/update the user's list entry from [record] (status/progress/score).
  /// Returns true on success.
  Future<bool> push(TrackRecord record);
}
