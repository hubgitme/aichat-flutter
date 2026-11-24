// رمزنگاریِ همگام‌سازی — پورتِ دقیقِ js/sync-crypto.js.
// «کد همگام‌سازی» هیچ‌وقت به سرور فرستاده نمی‌شود؛ از روی آن دو چیز مشتق
// می‌شود: syncId (شناسهٔ فضای ذخیره‌سازی، ۶۴ حرف هگز) و کلید AES-GCM.
// قالب خروجی: base64( [1 بایت: نوع] [12 بایت: iv] [دادهٔ رمزشده + تگ 16 بایتی] )
// نوع ۱ = متن خام، نوع ۲ = فشرده‌شده با gzip قبل از رمزنگاری.

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/pointycastle.dart';

const syncAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const syncCodeChars = 20;
const _syncSalt = 'aichat-sync-v1';
const _pbkdf2Iterations = 100000;
const maxSyncItemChars = 800000;

/// کدِ همگام‌سازیِ جدید: ۲۰ حرف، در گروه‌های ۴تایی با «-».
String generateSyncCode() {
  final rnd = Random.secure();
  final chars = List.generate(
      syncCodeChars, (_) => syncAlphabet[rnd.nextInt(syncAlphabet.length)]);
  final raw = chars.join();
  return [
    for (var i = 0; i < raw.length; i += 4) raw.substring(i, i + 4),
  ].join('-');
}

/// یکسان‌سازیِ کد: حروف بزرگ، حذفِ همه‌چیز به‌جز A-Z و 0-9.
String normalizeSyncCode(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

bool isValidSyncCode(String input) {
  final n = normalizeSyncCode(input);
  return n.length == syncCodeChars &&
      n.split('').every(syncAlphabet.contains);
}

class DerivedSyncKeys {
  final Uint8List aesKey; // 32 بایت
  final String syncId; // 64 حرف هگز
  const DerivedSyncKeys(this.aesKey, this.syncId);
}

/// PBKDF2-HMAC-SHA256 با salt ثابت، ۱۰۰٬۰۰۰ تکرار، خروجی ۶۴ بایت:
/// ۳۲ بایت اول کلید AES و ۳۲ بایت دوم (هگز) syncId است.
DerivedSyncKeys deriveSyncKeys(String code) {
  final normalized = normalizeSyncCode(code);
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  derivator.init(Pbkdf2Parameters(
    Uint8List.fromList(utf8.encode(_syncSalt)),
    _pbkdf2Iterations,
    64,
  ));
  final out = Uint8List(64);
  derivator.deriveKey(
      Uint8List.fromList(utf8.encode(normalized)), 0, out, 0);
  final aesKey = Uint8List.fromList(out.sublist(0, 32));
  final syncId = out
      .sublist(32)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return DerivedSyncKeys(aesKey, syncId);
}

Uint8List _gcmCrypt(Uint8List key, Uint8List iv, Uint8List data,
    {required bool encrypt}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
        encrypt,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  return cipher.process(data);
}

/// رمزکردنِ یک مقدار JSON؛ نوع ۲ (gzip) در صورت امکان، وگرنه نوع ۱.
String encryptSyncJson(Uint8List aesKey, Object value) {
  var payload = Uint8List.fromList(utf8.encode(jsonEncode(value)));
  var kind = 1;
  try {
    payload = Uint8List.fromList(gzip.encode(payload));
    kind = 2;
  } catch (_) {
    // بدون فشرده‌سازی ادامه می‌دهیم.
  }
  final rnd = Random.secure();
  final iv = Uint8List.fromList(
      List.generate(12, (_) => rnd.nextInt(256)));
  final ct = _gcmCrypt(aesKey, iv, payload, encrypt: true);
  final out = Uint8List(1 + 12 + ct.length);
  out[0] = kind;
  out.setRange(1, 13, iv);
  out.setRange(13, out.length, ct);
  return base64.encode(out);
}

/// رمزگشاییِ یک بلابِ همگام‌سازی (نوع ۱ یا ۲).
dynamic decryptSyncJson(Uint8List aesKey, String b64) {
  late final Uint8List bytes;
  try {
    bytes = base64.decode(b64);
  } catch (_) {
    throw const FormatException('دادهٔ همگام‌سازی نامعتبر است.');
  }
  if (bytes.length < 14 || (bytes[0] != 1 && bytes[0] != 2)) {
    throw const FormatException('دادهٔ همگام‌سازی نامعتبر است.');
  }
  final iv = Uint8List.fromList(bytes.sublist(1, 13));
  late final Uint8List plain;
  try {
    plain = _gcmCrypt(aesKey, iv,
        Uint8List.fromList(bytes.sublist(13)), encrypt: false);
  } catch (_) {
    throw const FormatException(
        'رمزگشایی ناموفق بود (کد همگام‌سازی اشتباه است یا داده خراب شده).');
  }
  Uint8List raw = plain;
  if (bytes[0] == 2) {
    try {
      raw = Uint8List.fromList(gzip.decode(plain));
    } catch (_) {
      throw const FormatException('دادهٔ همگام‌سازی نامعتبر است.');
    }
  }
  return jsonDecode(utf8.decode(raw));
}
