// ذخیرهٔ فایل در پوشهٔ عمومی Downloads گوشی — با MediaStore و از طریق
// کانالِ نیتیو (android-main/MainActivity.kt). بدون پکیجِ جانبی.
// اگر ذخیره در Downloads به هر دلیلی نشد، به پوشهٔ خصوصیِ اپ برمی‌گردد
// (همان رفتار قبلی).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// نتیجهٔ ذخیره: مسیرِ نمایشی برای پیامک + اینکه در پوشهٔ عمومی است یا نه.
class SaveResult {
  final String displayPath;
  final bool isPublic;
  const SaveResult(this.displayPath, this.isPublic);
}

const _downloadsChannel = MethodChannel('aichat/downloads');

String _mimeFor(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
  if (lower.endsWith('.txt') ||
      lower.endsWith('.md') ||
      lower.endsWith('.csv') ||
      lower.endsWith('.log')) return 'text/plain';
  return 'application/octet-stream';
}

/// ذخیرهٔ بایت‌ها با نامِ داده‌شده در پوشهٔ Downloads.
Future<SaveResult> saveToDownloads({
  required List<int> bytes,
  required String filename,
}) async {
  try {
    final display = await _downloadsChannel.invokeMethod<String>(
      'saveToDownloads',
      <String, dynamic>{
        'bytes': Uint8List.fromList(bytes),
        'filename': filename,
        'mime': _mimeFor(filename),
      },
    );
    if (display != null && display.isNotEmpty) {
      return SaveResult(display, true);
    }
  } catch (_) {
    // ذخیره در Downloads نشد — به پوشهٔ خصوصیِ اپ برمی‌گردیم.
  }
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  return SaveResult(file.path, false);
}

/// نسخهٔ متنی (خروجی JSON گفت‌وگوها و کد).
Future<SaveResult> saveTextToDownloads({
  required String text,
  required String filename,
}) =>
    saveToDownloads(bytes: utf8.encode(text), filename: filename);
