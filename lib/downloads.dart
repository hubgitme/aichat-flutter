// ذخیرهٔ فایل در پوشهٔ عمومی Downloads گوشی — با MediaStore (بدون نیاز
// به مجوز ذخیره‌سازی در اندروید ۱۰ به بالا). اگر MediaStore به هر دلیلی
// نشد، به پوشهٔ خصوصیِ اپ برمی‌گردد (همان رفتار قبلی).

import 'dart:convert';
import 'dart:io';

import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';

/// نتیجهٔ ذخیره: مسیرِ نمایشی برای پیامک + اینکه در پوشهٔ عمومی است یا نه.
class SaveResult {
  final String displayPath;
  final bool isPublic;
  const SaveResult(this.displayPath, this.isPublic);
}

bool _mediaStoreReady = false;

Future<void> _ensureMediaStore() async {
  if (_mediaStoreReady) return;
  await MediaStore.ensureInitialized();
  _mediaStoreReady = true;
}

/// ذخیرهٔ بایت‌ها با نامِ داده‌شده در پوشهٔ Downloads.
Future<SaveResult> saveToDownloads({
  required List<int> bytes,
  required String filename,
}) async {
  try {
    final tmpDir = await getTemporaryDirectory();
    final tmp = File('${tmpDir.path}/$filename');
    await tmp.writeAsBytes(bytes, flush: true);
    await _ensureMediaStore();
    final info = await MediaStore().saveFile(
      tempFilePath: tmp.path,
      dirType: DirType.download,
      dirName: DirName.download,
    );
    if (info != null) {
      return SaveResult('Downloads/$filename', true);
    }
  } catch (_) {
    // خطای MediaStore — به پوشهٔ خصوصیِ اپ برمی‌گردیم.
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
