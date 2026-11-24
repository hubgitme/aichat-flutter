import 'dart:convert';
import 'dart:io';

import 'package:aichat/sync_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// بردارِ تستِ تولیدشده با پیاده‌سازیِ واقعیِ JS (js/sync-crypto.js) —
/// tool/gen_sync_vector.mjs. اگر این تست در CI پاس شود، یعنی پیاده‌سازیِ
/// Dart با نسخهٔ وب سازگار است (هم syncId، هم رمزگشاییِ بلاب‌های kind=1 و
/// kind=2 که وب ساخته است).
Future<Map<String, dynamic>> loadVector() async {
  final raw = await File('test/sync_vector.json').readAsString();
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  late Map<String, dynamic> vector;

  setUpAll(() async {
    vector = await loadVector();
  });

  test('deriveSyncKeys matches the JS implementation', () {
    final keys = deriveSyncKeys(vector['code'] as String);
    expect(keys.syncId, vector['syncId']);
    expect(
      keys.aesKey
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      vector['aesKeyHex'],
    );
  });

  test('decrypts blobs produced by the real JS (kind 1, kind 2, js blob)',
      () {
    final keys = deriveSyncKeys(vector['code'] as String);
    final expected = vector['plaintext'];
    for (final field in ['kind1Blob', 'kind2Blob', 'jsBlob']) {
      final decoded = decryptSyncJson(keys.aesKey, vector[field] as String);
      expect(decoded, expected, reason: field);
    }
  });

  test('encrypt/decrypt round-trip', () {
    final keys = deriveSyncKeys('ABCD-EFGH-JKLM-NPQR-STUV');
    final value = {
      'id': 'x',
      'title': 'تست',
      'messages': [
        {'role': 'user', 'content': 'سلام 👋'},
      ],
    };
    final blob = encryptSyncJson(keys.aesKey, value);
    expect(blob.length, lessThan(maxSyncItemChars));
    expect(decryptSyncJson(keys.aesKey, blob), value);
  });

  test('wrong code fails to decrypt', () {
    final keys = deriveSyncKeys(vector['code'] as String);
    final other = deriveSyncKeys('2222-3333-4444-5555-6666');
    final blob = encryptSyncJson(keys.aesKey, {'a': 1});
    expect(() => decryptSyncJson(other.aesKey, blob), throwsFormatException);
  });

  test('code generation and validation', () {
    final code = generateSyncCode();
    expect(isValidSyncCode(code), isTrue);
    expect(code.split('-').length, 5);
    expect(code.replaceAll('-', '').length, 20);
    expect(isValidSyncCode('ABCD-EFGH-JKLM-NPQR-STUV'), isTrue);
    // حروف I و O و 0 و 1 در الفبا نیستند
    expect(isValidSyncCode('IIII-OOOO-0000-1111-2222'), isFalse);
    expect(isValidSyncCode('short'), isFalse);
    expect(isValidSyncCode('abcd-efgh-jklm-npqr-stuv'), isTrue);
  });
}
