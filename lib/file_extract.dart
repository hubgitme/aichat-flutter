// استخراج متن از فایل‌های پیوستی — همان منطق نسخهٔ وب (js/files.js):
// عکس‌ها جدا به‌عنوان vision فرستاده می‌شن؛ فایل‌های متنی و کد (txt/md/
// json/js/html/css/py/...) متن‌شون این‌جا خوانده و به متن پیام کاربر
// اضافه می‌شه. فایل‌های آفیس (Word/PDF) پشتیبانی نمی‌شوند.
// خالص (بدون Flutter) تا در تست هم قابل‌استفاده باشد.

import 'dart:convert';

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

/// پسوندهای فایل‌های متنی و کد (همان DOCUMENT_EXT_RE در js/files.js
/// بدون پسوندهای آفیس).
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
};

/// پسوندهای آفیس (پشتیبانی نمی‌شوند).
const Set<String> officeExtensions = {'doc', 'docx', 'pdf'};

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

/// استخراج متن از یک فایل (همان extractTextFromFile در js/files.js).
/// در صورت خطا FileExtractException با همان پیام وب پرتاب می‌شود.
String extractTextFromFileBytes(String name, List<int> bytes) {
  if (bytes.length > maxSingleFileBytes) {
    throw FileExtractException(
        'حجم فایل «$name» بیش از حد مجاز است (حداکثر ۵ مگابایت).');
  }
  if (officeExtensions.contains(fileExtension(name))) {
    throw const FileExtractException(
        'فایل‌های آفیس (Word و PDF) پشتیبانی نمی‌شوند.');
  }
  final text = utf8.decode(bytes, allowMalformed: true).trim();
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
