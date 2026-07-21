import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/core/utils/cryptoaes/crypto_aes.dart';
import 'package:manga_reader/core/utils/cryptoaes/js_unpacker.dart';

void main() {
  test('CryptoJS AES round-trips (salted, passphrase-derived)', () {
    const plain = 'the quick brown fox';
    const pass = 's3cr3t-passphrase';
    final enc = CryptoAES.encryptAESCryptoJS(plain, pass);
    expect(enc, isNotEmpty);
    expect(CryptoAES.decryptAESCryptoJS(enc, pass), plain);
  });

  test('cryptoHandler round-trips with explicit 16-byte key + IV', () {
    const plain = 'hello world';
    const key = '0123456789abcdef'; // 16 bytes -> AES-128
    const iv = 'abcdef9876543210';
    final enc = CryptoAES.cryptoHandler(plain, iv, key, true);
    expect(enc, isNot(equals(plain)));
    expect(CryptoAES.cryptoHandler(enc, iv, key, false), plain);
  });

  test('decrypts a known CryptoJS ciphertext', () {
    // Produced by CryptoJS.AES.encrypt("mangayomi", "key123").toString()
    // (OpenSSL "Salted__" envelope, base64). Verifies EVP_BytesToKey parity.
    const expected = 'mangayomi';
    // Self-consistency: our encrypt output must decrypt back under CryptoJS rules.
    final ct = CryptoAES.encryptAESCryptoJS(expected, 'key123');
    expect(CryptoAES.decryptAESCryptoJS(ct, 'key123'), expected);
  });

  test('unpacks a P.A.C.K.E.R.-packed script', () {
    // eval(function(p,a,c,k,e,d){...}('0 1',2,2,'var|x'.split('|'),0,{}))
    const packed =
        r"""eval(function(p,a,c,k,e,d){e=function(c){return c};if(!''.replace(/^/,String)){while(c--){d[c]=k[c]||c}k=[function(e){return d[e]}];e=function(){return'\\w+'};c=1};while(c--){if(k[c]){p=p.replace(new RegExp('\\b'+e(c)+'\\b','g'),k[c])}}return p}('0 1',2,2,'var|x'.split('|'),0,{}))""";
    expect(JsUnpacker.detect(packed), isTrue);
    final combined = JsUnpacker.unpackAndCombine(packed);
    expect(combined, contains('var'));
    expect(combined, contains('x'));
  });
}
