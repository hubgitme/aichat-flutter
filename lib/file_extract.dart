// استخراج متن از فایل‌های پیوستی — همان منطق نسخهٔ وب (js/files.js):
// عکس‌ها جدا به‌عنوان vision فرستاده می‌شن؛ فایل‌های سند و کد (txt/md/
// json/js/html/css/py/... + PDF + Word) متن‌شون این‌جا استخراج و به متن
// پیام کاربر اضافه می‌شه. خالص (بدون Flutter) تا در تست هم قابل‌استفاده باشد.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// سقف حجم هر فایل (همان وب).
const int maxSingleFileBytes = 5 * 1024 * 1024;

/// سقف کاراکترِ متنِ استخراج‌شده (همان وب).
const int maxExtractChars = 15000;

/// خطای قابل‌نمایش به کاربر؛ toString دقیقاً همان پیام وب است.
class FileExtractException implements Exception {
  final String message;
  const FileExtractException(this.message);
  @override
  String toString() => message;
}

/// یک فایلِ سندِ استخراج‌شده (نام + متن).
class AttachedDoc {
  final String name;
  final String text;
  const AttachedDoc({required this.name, required this.text});
}

/// پسوندهای فایل‌های سند و کد (همان DOCUMENT_EXT_RE در js/files.js).
const Set<String> documentExtensions = {
  // متن ساده و مستندات
  'txt', 'md', 'markdown', 'rst', 'log', 'csv', 'tsv',
  // داده/تنظیمات
  'json', 'jsonc', 'xml', 'yaml', 'yml', 'toml', 'ini', 'env', 'cfg', 'conf',
  // وب
  'html', 'htm', 'css', 'scss', 'sass', 'less', 'svg',
  // جاوااسکریپت/تایپ‌اسکریپت
  'js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'vue', 'svelte',
  // زبان‌های برنامه‌نویسی رایج
  'py', 'java', 'kt', 'go', 'rs', 'rb', 'php', 'c', 'h', 'cpp', 'hpp', 'cs',
  'swift', 'dart', 'lua', 'pl', 'r', 'scala', 'sql',
  // اسکریپت/شل
  'sh', 'bash', 'zsh', 'ps1', 'bat',
  // سند آفیس و PDF
  'docx', 'doc', 'pdf',
};

/// پسوندهای عکس (همان file.type.startsWith('image/') در وب).
const Set<String> imageExtensions = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif',
};

/// همهٔ پسوندهای قابل‌انتخاب در فایل‌پیکر (سند + عکس).
const List<String> pickableExtensions = [
  ...documentExtensions,
  ...imageExtensions,
];

/// پسوند فایل (بدون نقطه، با حروف کوچک)؛ اگر پسوندی نداشت '' است.
String fileExtension(String name) {
  final idx = name.lastIndexOf('.');
  if (idx < 0 || idx == name.length - 1) return '';
  return name.substring(idx + 1).toLowerCase();
}

bool isDocumentFileName(String name) =>
    documentExtensions.contains(fileExtension(name));

bool isImageFileName(String name) =>
    imageExtensions.contains(fileExtension(name));

String _truncate(String text) {
  if (text.length <= maxExtractChars) return text;
  return '${text.substring(0, maxExtractChars)}\n\n[...متن به‌خاطر حجم زیاد، بریده شد...]';
}

/// استخراج متن از DOCX: فایل ZIP است؛ word/document.xml خوانده و
/// محتوای تگ‌های `<w:t>` (متنِ runها) با خطِ جدید بین پاراگراف‌ها برمی‌گردد.
String extractTextFromDocxBytes(List<int> bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) return '';
    final xml = utf8.decode(entry.content, allowMalformed: true);
    final runRe = RegExp(r'<w:t[^>]*>([^<]*)</w:t>');
    final paragraphs = <String>[];
    for (final part in xml.split('</w:p>')) {
      final runs = <String>[];
      for (final m in runRe.allMatches(part)) {
        runs.add(m.group(1) ?? '');
      }
      paragraphs.add(runs.join(''));
    }
    return paragraphs.join('\n');
  } catch (_) {
    return '';
  }
}

/// حذف escapeهای رشته‌های literal در PDF و برگرداندن متن.
String _pdfUnescape(String literal) {
  // literal شامل پرانتزهای دورِ رشته است.
  final inner = literal.substring(1, literal.length - 1);
  final bytes = <int>[];
  var i = 0;
  while (i < inner.length) {
    final c = inner.codeUnitAt(i);
    if (c == 0x5C && i + 1 < inner.length) {
      // بک‌اسلش: escape بعدی.
      final n = inner.codeUnitAt(i + 1);
      if (n >= 0x30 && n <= 0x37) {
        // octal تا ۳ رقم.
        var val = 0;
        var j = i + 1;
        var count = 0;
        while (j < inner.length &&
            count < 3 &&
            inner.codeUnitAt(j) >= 0x30 &&
            inner.codeUnitAt(j) <= 0x37) {
          val = val * 8 + (inner.codeUnitAt(j) - 0x30);
          j++;
          count++;
        }
        bytes.add(val);
        i = j;
        continue;
      }
      switch (n) {
        case 0x6E: // n
          bytes.add(0x0A);
          break;
        case 0x72: // r
          bytes.add(0x0D);
          break;
        case 0x74: // t
          bytes.add(0x09);
          break;
        case 0x62: // b
          bytes.add(0x08);
          break;
        case 0x66: // f
          bytes.add(0x0C);
          break;
        case 0x0A: // newline بعد از بک‌اسلش نادیده گرفته می‌شود
        case 0x0D:
          break;
        default:
          bytes.add(n);
      }
      i += 2;
      continue;
    }
    bytes.add(c > 0xFF ? 0x3F : c);
    i++;
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    // UTF-16BE با BOM.
    final units = <int>[];
    for (var k = 2; k + 1 < bytes.length; k += 2) {
      units.add((bytes[k] << 8) | bytes[k + 1]);
    }
    return String.fromCharCodes(units);
  }
  return String.fromCharCodes(bytes);
}

/// متنِ یک استریمِ PDF (به‌صورت رشتهٔ latin1): رشته‌های literalِ
/// عملگرهای Tj و TJ را بیرون می‌کشد.
String _pdfTextFromStream(String s) {
  final out = <String>[];
  final literalRe = RegExp(r'\((?:\\.|[^()\\])*\)');
  // (...) Tj
  final tjRe = RegExp(r'(\((?:\\.|[^()\\])*\))\s*Tj');
  for (final m in tjRe.allMatches(s)) {
    final lit = m.group(1);
    if (lit != null) out.add(_pdfUnescape(lit));
  }
  // [...] TJ — آرایه‌ای از رشته‌ها و اعداد.
  final tjArrayRe = RegExp(r'\[([^\]]*)\]\s*TJ');
  for (final m in tjArrayRe.allMatches(s)) {
    final inner = m.group(1) ?? '';
    for (final sm in literalRe.allMatches(inner)) {
      out.add(_pdfUnescape(sm.group(0)!));
    }
  }
  return out.join(' ');
}

/// استخراج متن از PDF — بهترین تلاشِ ممکن (فقط با Dart):
/// استریم‌ها پیدا و در صورت FlateDecode با ZLibDecoder باز می‌شوند، بعد
/// رشته‌های عملگرهای Tj/TJ خوانده می‌شوند. اگر چیزی خوانا نبود '' است.
String extractTextFromPdfBytes(List<int> bytes) {
  try {
    // latin1: هر بایت دقیقاً یک code unit می‌شود و برمی‌گردد.
    final raw = String.fromCharCodes(bytes);
    final parts = <String>[];
    var pos = 0;
    while (true) {
      final streamIdx = raw.indexOf('stream', pos);
      if (streamIdx < 0) break;
      // خودِ 'endstream' را با 'stream' اشتباه نگیریم.
      if (streamIdx >= 3 && raw.substring(streamIdx - 3, streamIdx) == 'end') {
        pos = streamIdx + 6;
        continue;
      }
      var dataStart = streamIdx + 6;
      if (dataStart < raw.length && raw[dataStart] == '\r') dataStart++;
      if (dataStart < raw.length && raw[dataStart] == '\n') dataStart++;
      final endIdx = raw.indexOf('endstream', dataStart);
      if (endIdx < 0) break;
      var dataEnd = endIdx;
      if (dataEnd > dataStart && raw[dataEnd - 1] == '\n') dataEnd--;
      if (dataEnd > dataStart && raw[dataEnd - 1] == '\r') dataEnd--;
      final chunk = raw.substring(dataStart, dataEnd);
      String text;
      try {
        final inflated = zlib.decode(chunk.codeUnits);
        text = String.fromCharCodes(inflated);
      } catch (_) {
        text = chunk;
      }
      final extracted = _pdfTextFromStream(text);
      if (extracted.trim().isNotEmpty) parts.add(extracted);
      pos = endIdx + 9;
    }
    return parts.join('\n');
  } catch (_) {
    return '';
  }
}

/// استخراج متن از یک فایل (همان extractTextFromFile در js/files.js).
/// در صورت خطا FileExtractException با همان پیام وب پرتاب می‌شود.
String extractTextFromFileBytes(String name, List<int> bytes) {
  if (bytes.length > maxSingleFileBytes) {
    throw FileExtractException(
        'حجم فایل «$name» بیش از حد مجاز است (حداکثر ۵ مگابایت).');
  }
  final lower = name.toLowerCase();
  String text;
  if (lower.endsWith('.pdf')) {
    text = extractTextFromPdfBytes(bytes);
  } else if (lower.endsWith('.docx')) {
    text = extractTextFromDocxBytes(bytes);
  } else if (lower.endsWith('.doc')) {
    throw const FileExtractException(
        'فرمت قدیمی .doc پشتیبانی نمی‌شود — لطفاً به .docx یا PDF تبدیل کن.');
  } else {
    text = utf8.decode(bytes, allowMalformed: true);
  }
  text = text.trim();
  if (text.isEmpty) {
    throw const FileExtractException(
        'متنی از این فایل استخراج نشد (شاید اسکن‌شده یا خالی باشد).');
  }
  return _truncate(text);
}

/// بلوکِ متنِ فایل‌ها برای اضافه‌شدن به پیام (همان docsBlock در js/ui.js).
String buildDocsBlock(List<AttachedDoc> docs) {
  if (docs.isEmpty) return '';
  final parts = docs
      .map((d) =>
          '--- محتوای فایل «${d.name}» ---\n${d.text}\n--- پایان فایل «${d.name}» ---')
      .join('\n\n');
  return '\n\n$parts';
}
