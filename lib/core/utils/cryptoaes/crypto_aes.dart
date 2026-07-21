import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// CryptoJS-compatible AES helpers used by JS/Dart source extensions.
/// Ported from Mangayomi so unmodified extensions that call
/// `encryptAESCryptoJS` / `decryptAESCryptoJS` / `cryptoHandler` work as-is.
class CryptoAES {
  static String encryptAESCryptoJS(String plainText, String passphrase) {
    final salt = genRandomWithNonZero(8);
    final keyndIV = deriveKeyAndIV(passphrase.trim(), salt);
    final key = encrypt.Key(keyndIV.$1);
    final iv = encrypt.IV(keyndIV.$2);

    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );
    final encrypted = encrypter.encrypt(plainText.trim(), iv: iv);
    final encryptedBytesWithSalt = Uint8List.fromList(
      createUint8ListFromString('Salted__') + salt + encrypted.bytes,
    );
    return base64.encode(encryptedBytesWithSalt);
  }

  static String decryptAESCryptoJS(String encrypted, String passphrase) {
    final encryptedBytesWithSalt = base64.decode(encrypted.trim());
    final encryptedBytes =
        encryptedBytesWithSalt.sublist(16, encryptedBytesWithSalt.length);
    final salt = encryptedBytesWithSalt.sublist(8, 16);
    final keyndIV = deriveKeyAndIV(passphrase.trim(), salt);
    final key = encrypt.Key(keyndIV.$1);
    final iv = encrypt.IV(keyndIV.$2);

    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );
    return encrypter.decrypt64(base64.encode(encryptedBytes), iv: iv);
  }

  /// AES-CBC with an explicit UTF-8 key + IV. [encryptMode] true = encrypt
  /// (returns base64), false = decrypt (input is base64). Returns [text]
  /// unchanged on error, mirroring upstream behaviour.
  static String cryptoHandler(
    String text,
    String iv,
    String secretKeyString,
    bool encryptMode,
  ) {
    try {
      final key = encrypt.Key.fromUtf8(secretKeyString);
      final ivv = encrypt.IV.fromUtf8(iv);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
      );
      if (encryptMode) {
        return encrypter.encrypt(text, iv: ivv).base64;
      }
      return encrypter.decrypt64(text, iv: ivv);
    } catch (_) {
      return text;
    }
  }

  static (Uint8List, Uint8List) deriveKeyAndIV(
    String passphrase,
    Uint8List salt,
  ) {
    final password = createUint8ListFromString(passphrase);
    var concatenatedHashes = Uint8List(0);
    var currentHash = Uint8List(0);
    var enoughBytesForKey = false;
    Uint8List preHash;

    while (!enoughBytesForKey) {
      if (currentHash.isNotEmpty) {
        preHash = Uint8List.fromList(currentHash + password + salt);
      } else {
        preHash = Uint8List.fromList(password + salt);
      }

      currentHash = Uint8List.fromList(md5.convert(preHash).bytes);
      concatenatedHashes = Uint8List.fromList(concatenatedHashes + currentHash);
      if (concatenatedHashes.length >= 48) enoughBytesForKey = true;
    }

    final keyBytes = concatenatedHashes.sublist(0, 32);
    final ivBytes = concatenatedHashes.sublist(32, 48);
    return (keyBytes, ivBytes);
  }

  static Uint8List createUint8ListFromString(String s) {
    final ret = Uint8List(s.length);
    for (var i = 0; i < s.length; i++) {
      ret[i] = s.codeUnitAt(i);
    }
    return ret;
  }

  static Uint8List genRandomWithNonZero(int seedLength) {
    final random = Random.secure();
    const int randomMax = 245;
    final uint8list = Uint8List(seedLength);
    for (int i = 0; i < seedLength; i++) {
      uint8list[i] = random.nextInt(randomMax) + 1;
    }
    return uint8list;
  }
}
