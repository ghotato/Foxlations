import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// Supplies the AES key used to encrypt Hive boxes that hold credentials.
///
/// The key itself lives in the platform keystore — iOS Keychain, Android
/// EncryptedSharedPreferences backed by the hardware Keystore — not in the
/// app's data directory. So an attacker who copies the app's files (a rooted
/// device, an unencrypted backup, a stolen sandbox) gets ciphertext with no key.
///
/// This protects OAuth access and refresh tokens, which were previously stored
/// in a plaintext Hive box: anyone reading that file could impersonate the user
/// against AniList / MyAnimeList / Kitsu until the tokens expired.
class SecureStore {
  static const _keyName = 'foxlations_box_key_v1';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      // Available after first unlock, so background work still runs, but the
      // key never leaves the device in an iCloud/iTunes backup.
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static HiveAesCipher? _cipher;

  /// Cipher for credential-bearing boxes, or null when the keystore is
  /// unavailable (see [initialize]).
  static HiveAesCipher? get cipher => _cipher;

  /// Loads the key, generating one on first run.
  ///
  /// Returns false if the platform keystore can't be reached — some Android
  /// devices have a broken Keystore, and losing access to it would otherwise
  /// make the app unable to open its own boxes. Callers fall back to an
  /// unencrypted box in that case: degraded, but the alternative is an app that
  /// won't start.
  static Future<bool> initialize() async {
    try {
      var encoded = await _storage.read(key: _keyName);
      if (encoded == null) {
        final rng = Random.secure();
        final key =
            Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
        encoded = base64Encode(key);
        await _storage.write(key: _keyName, value: encoded);
      }
      _cipher = HiveAesCipher(base64Decode(encoded));
      return true;
    } catch (e) {
      debugPrint('[SecureStore] keystore unavailable, boxes stay plaintext: $e');
      _cipher = null;
      return false;
    }
  }
}
