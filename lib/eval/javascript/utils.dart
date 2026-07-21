import 'package:flutter_js/flutter_js.dart';

import '../../core/utils/cryptoaes/crypto_aes.dart';
import '../../core/utils/cryptoaes/deobfuscator.dart';
import '../../core/utils/cryptoaes/js_unpacker.dart';
import 'package:js_packer/js_packer.dart';

/// Injects utility functions into the JS runtime.
///
/// This provides the CryptoJS-compatible AES helpers, JSFuck deobfuscation and
/// Dean-Edwards P.A.C.K.E.R. unpacking that Mangayomi JS source extensions call
/// synchronously (`decryptAESCryptoJS`, `cryptoHandler`, `unpackJs`, …), plus
/// the Kotlin-style `String` helpers those sources rely on. `flutter_js`'s
/// `sendMessage` resolves synchronously on the QuickJS runtime, so these shims
/// return their result directly (no `await`), matching how sources invoke them.
class JsUtils {
  final JavascriptRuntime _runtime;

  JsUtils(this._runtime);

  void init() {
    // --- Crypto (CryptoJS-compatible AES). Handlers return the input
    // unchanged on failure, mirroring upstream Mangayomi behaviour. ---
    _runtime.onMessage('cryptoHandler', (dynamic args) {
      // args: [text, iv, secretKeyString, encrypt]
      try {
        return CryptoAES.cryptoHandler(
          args[0] as String,
          args[1] as String,
          args[2] as String,
          args[3] as bool,
        );
      } catch (_) {
        return args[0];
      }
    });
    _runtime.onMessage('encryptAESCryptoJS', (dynamic args) {
      try {
        return CryptoAES.encryptAESCryptoJS(
            args[0] as String, args[1] as String);
      } catch (_) {
        return args[0];
      }
    });
    _runtime.onMessage('decryptAESCryptoJS', (dynamic args) {
      try {
        return CryptoAES.decryptAESCryptoJS(
            args[0] as String, args[1] as String);
      } catch (_) {
        return args[0];
      }
    });
    _runtime.onMessage('deobfuscateJsPassword', (dynamic args) {
      try {
        return Deobfuscator.deobfuscateJsPassword(args[0] as String);
      } catch (_) {
        return args[0];
      }
    });

    // --- JS Unpacker (Dean Edwards' P.A.C.K.E.R.) ---
    _runtime.onMessage('unpackJsAndCombine', (dynamic args) {
      try {
        return JsUnpacker.unpackAndCombine(args[0] as String) ?? args[0];
      } catch (_) {
        return args[0];
      }
    });
    _runtime.onMessage('unpackJs', (dynamic args) {
      try {
        return JSPacker(args[0] as String).unpack() ?? args[0];
      } catch (_) {
        return args[0];
      }
    });

    _runtime.evaluate('''
async function jsonStringify(fn) {
    return JSON.stringify(await fn());
}

function slugify(text) {
    return text.toString().toLowerCase()
        .replace(/\\s+/g, '-')
        .replace(/[^\\w\\-]+/g, '')
        .replace(/\\-\\-+/g, '-')
        .replace(/^-+/, '')
        .replace(/-+\$/, '');
}

// --- Crypto / unpacker bridge shims (synchronous on QuickJS) ---
function cryptoHandler(text, iv, secretKeyString, encrypt) {
    return sendMessage(
        "cryptoHandler",
        JSON.stringify([text, iv, secretKeyString, encrypt])
    );
}
function encryptAESCryptoJS(plainText, passphrase) {
    return sendMessage(
        "encryptAESCryptoJS",
        JSON.stringify([plainText, passphrase])
    );
}
function decryptAESCryptoJS(encrypted, passphrase) {
    return sendMessage(
        "decryptAESCryptoJS",
        JSON.stringify([encrypted, passphrase])
    );
}
function deobfuscateJsPassword(inputString) {
    return sendMessage(
        "deobfuscateJsPassword",
        JSON.stringify([inputString])
    );
}
function unpackJsAndCombine(scriptBlock) {
    return sendMessage(
        "unpackJsAndCombine",
        JSON.stringify([scriptBlock])
    );
}
function unpackJs(packedJS) {
    return sendMessage(
        "unpackJs",
        JSON.stringify([packedJS])
    );
}

// --- Kotlin-style String helpers used by Mangayomi sources ---
String.prototype.substringAfter = function(pattern) {
    const startIndex = this.indexOf(pattern);
    if (startIndex === -1) return this.substring(0);
    const start = startIndex + pattern.length;
    return this.substring(start);
}
String.prototype.substringAfterLast = function(pattern) {
    return this.split(pattern).pop();
}
String.prototype.substringBefore = function(pattern) {
    const endIndex = this.indexOf(pattern);
    if (endIndex === -1) return this.substring(0);
    return this.substring(0, endIndex);
}
String.prototype.substringBeforeLast = function(pattern) {
    const endIndex = this.lastIndexOf(pattern);
    if (endIndex === -1) return this.substring(0);
    return this.substring(0, endIndex);
}
String.prototype.substringBetween = function(left, right) {
    let startIndex = 0;
    let index = this.indexOf(left, startIndex);
    if (index === -1) return "";
    let leftIndex = index + left.length;
    let rightIndex = this.indexOf(right, leftIndex);
    if (rightIndex === -1) return "";
    return this.substring(leftIndex, rightIndex);
}
''');
  }
}
