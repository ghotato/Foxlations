import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

/// Key derivation and verification for the vault.
///
/// Replaces a 32-bit FNV checksum that was previously used as a "password
/// hash". That scheme was unsalted, instant to compute and trivially collided,
/// and — more importantly — the vault's data boxes were stored in plaintext
/// regardless, so anyone with the Hive files could read everything without
/// knowing the password at all.
///
/// Now: PBKDF2-HMAC-SHA256 derives a 256-bit key from the password and a random
/// per-install salt; that key encrypts the vault's Hive boxes via
/// [HiveAesCipher]. The key is never stored — only a hash of it, so verifying a
/// password doesn't reveal the key, and without the password the boxes cannot
/// be opened at all.
class VaultCrypto {
  /// Cost factor. Pure-Dart PBKDF2 is slower than a native implementation, so
  /// this is a compromise between unlock latency on a phone (~1s) and brute
  /// force resistance. Raising it is safe: [deriveKey] is only ever called with
  /// the salt stored alongside, and old vaults keep working because the
  /// iteration count is persisted per vault.
  static const int defaultIterations = 50000;
  static const int _keyLength = 32; // 256-bit, required by HiveAesCipher
  static const int _saltLength = 16;

  static Uint8List newSalt() {
    final rng = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(_saltLength, (_) => rng.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018). Implemented here rather than pulled from a
  /// package because `crypto` already provides HMAC and this avoids adding a
  /// dependency for ~20 lines.
  static Uint8List deriveKey(
    String password,
    Uint8List salt, {
    int iterations = defaultIterations,
  }) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final output = BytesBuilder();
    var block = 1;

    while (output.length < _keyLength) {
      // U1 = PRF(password, salt || INT_32_BE(block))
      final seed = Uint8List.fromList([
        ...salt,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ]);
      var u = Uint8List.fromList(hmac.convert(seed).bytes);
      final accumulated = Uint8List.fromList(u);

      // T = U1 xor U2 xor ... xor Uc
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < accumulated.length; j++) {
          accumulated[j] ^= u[j];
        }
      }
      output.add(accumulated);
      block++;
    }
    return Uint8List.fromList(output.toBytes().sublist(0, _keyLength));
  }

  /// Stored instead of the key itself, so the on-disk record can verify a
  /// password without being sufficient to decrypt anything.
  static String verifierFor(Uint8List key) =>
      sha256.convert([...key, ...utf8.encode('foxlations-vault-v1')]).toString();

  static HiveAesCipher cipherFor(Uint8List key) => HiveAesCipher(key);
}
