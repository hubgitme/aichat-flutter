// ابزارهای خالص (بدون Flutter) — همان منطق نسخهٔ وب (js/urlread.js،
// js/search.js، js/history.js و بخش کد طولانی در js/render.js).

import 'models.dart';

/// استخراج آدرس‌ها از متن؛ نقطه‌گذاریِ چسبیده به آخر لینک حذف و تکراری‌ها
/// یکی می‌شوند (همان URL_RE در js/urlread.js).
List<String> extractUrls(String text) {
  final re = RegExp(r"https?://[^\s<>\"\"')\]]+");
  final found = <String>[];
  for (final m in re.allMatches(text)) {
    final url = m.group(0)!.replaceAll(RegExp(r'[.,،;!?]+$'), '');
    if (url.isNotEmpty && !found.contains(url)) found.add(url);
  }
  return found;
}

/// کدِ طولانی: ۱۲۰۰ کاراکتر یا ۳۰ خط یا بیشتر (همان آستانهٔ نسخهٔ وب).
bool isLongCode(String code) {
  if (code.length >= 1200) return true;
  return '\n'.allMatches(code).length + 1 >= 30;
}

/// نام فایلِ پایدار برای دانلود کد بر اساس زبان (همان نسخهٔ وب).
String filenameForLang(String lang) {
  switch (lang.toLowerCase()) {
    case 'python':
    case 'py':
      return 'script.py';
    case 'javascript':
    case 'js':
    case 'typescript':
    case 'ts':
      return 'script.js';
    case 'html':
      return 'index.html';
    case 'css':
      return 'style.css';
    case 'json':
      return 'data.json';
    default:
      return 'code.txt';
  }
}

/// پیامِ کانتکستِ جست‌وجوی وب (همان buildSearchContextMessage در
/// js/search.js).
String buildSearchContextMessage(String query, List<Source> results) {
  if (results.isEmpty) {
    return 'جست‌وجوی وب برای «$query» نتیجه‌ای نداشت. بر اساس دانش خودت جواب بده و بگو که جست‌وجو نتیجه‌ای نداشت.';
  }
  final list = results
      .asMap()
      .entries
      .map((e) => '[${e.key + 1}] ${e.value.title}\n${e.value.url}\n${e.value.snippet}')
      .join('\n\n');
  return 'نتایج جست‌وجوی وب برای «$query»:\n\n$list\n\nبر اساس این نتایج (و در صورت نیاز دانش خودت) به فارسی و به‌صورت خلاصه و دقیق جواب بده. هرجا از یک نتیجه استفاده کردی با شماره‌اش [۱] مشخص کن.';
}

/// کانتکستِ خواندن صفحه (همان buildUrlContextMessage در js/urlread.js).
String buildUrlContextMessage(String url, Map<String, dynamic> data) {
  final title = (data['title'] as String?)?.isNotEmpty == true
      ? ' (عنوان: ${data['title']})'
      : '';
  final truncNote = data['truncated'] == true
      ? '\n\nتوجه: متن صفحه طولانی بود و فقط ۲۰٬۰۰۰ کاراکتر اول آن خوانده شده؛ در جوابت بگو که خلاصه/ترجمه فقط بر اساس ابتدای صفحه است.'
      : '';
  return 'محتوای صفحهٔ ${data['url'] ?? url}$title:\n\n${data['text']}$truncNote\n\nبر اساس همین متن به درخواست کاربر جواب بده: اگر خلاصه خواست خلاصه بده، اگر ترجمه خواست به فارسی ترجمه کن، اگر سوالی دربارهٔ صفحه پرسید از همین متن جواب بده. چیزی که در این متن نیست را از خودت اضافه نکن.';
}

/// کانتکستِ خطای خواندن صفحه — مدل نباید محتوا را از خودش بسازد.
String buildUrlErrorContextMessage(String url, String message) {
  return 'خواندن صفحهٔ $url با خطا مواجه شد: $message. به کاربر بگو که نتوانستی صفحه را بخوانی و محتوا را از خودت نساز.';
}

// --- پنجرهٔ لغزان تاریخچه (همان js/history.js) ---

const maxHistoryMessages = 40;
const maxHistoryChars = 60000;

int _contentLength(dynamic content) {
  if (content is String) return content.length;
  if (content is List) {
    var n = 0;
    for (final part in content) {
      if (part is Map &&
          part['type'] == 'text' &&
          part['text'] is String) {
        n += (part['text'] as String).length;
      }
    }
    return n;
  }
  return 0;
}

class TrimmedHistory {
  final List<Map<String, dynamic>> messages;
  final int dropped;
  const TrimmedHistory(this.messages, this.dropped);
}

/// فقط آخرین پیام‌ها (در سقف تعداد و کاراکتر) برای مدل فرستاده می‌شوند؛
/// جدیدترین پیام همیشه می‌ماند و لیست نباید با پیام assistant شروع شود.
TrimmedHistory trimHistory(List<Map<String, dynamic>> messages,
    {int maxMessages = maxHistoryMessages, int maxChars = maxHistoryChars}) {
  final kept = <Map<String, dynamic>>[];
  var chars = 0;
  for (var i = messages.length - 1; i >= 0; i--) {
    final len = _contentLength(messages[i]['content']);
    final isNewest = kept.isEmpty;
    if (!isNewest && (kept.length >= maxMessages || chars + len > maxChars)) {
      break;
    }
    kept.add(messages[i]);
    chars += len;
  }
  final out = kept.reversed.toList();
  while (out.length > 1 && out.first['role'] != 'user') {
    out.removeAt(0);
  }
  return TrimmedHistory(out, messages.length - out.length);
}

/// ساخت پیام‌های API از گفت‌وگو: پیام‌های ساخته‌شدهٔ تصویر/ویدیو و پیام‌های
/// خطا/خالی فرستاده نمی‌شوند؛ عکس‌ها به آخرین پیام کاربر وصل می‌شوند
/// (همان buildApiMessages در js/ui.js).
List<Map<String, dynamic>> buildApiMessages(
  Conversation conv, {
  List<String>? images,
  String? context,
}) {
  const systemPrompt =
      'You are a helpful, friendly AI assistant. Always respond in the same language the user writes in (mostly Persian). Format code with proper markdown code fences and a language tag.';
  final history = <Map<String, dynamic>>[];
  for (final m in conv.messages) {
    if (m.role != 'user' && m.role != 'assistant') continue;
    if (m.generatedImage || m.generatedVideo) continue;
    final hasText =
        (m.apiContent ?? m.content).isNotEmpty;
    final hasImage = m.role == 'user' && m.images != null && m.images!.isNotEmpty;
    if (m.error || (!hasText && !hasImage)) continue;
    history.add({'role': m.role, 'content': m.apiContent ?? m.content});
  }
  final trimmed = trimHistory(history);
  final apiMessages = <Map<String, dynamic>>[
    {'role': 'system', 'content': systemPrompt},
    ...trimmed.messages,
  ];
  if (context != null && context.isNotEmpty) {
    apiMessages.add({'role': 'system', 'content': context});
  }
  if (images != null && images.isNotEmpty) {
    var lastUserIdx = -1;
    for (var i = apiMessages.length - 1; i >= 0; i--) {
      if (apiMessages[i]['role'] == 'user') {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx != -1) {
      final lastText = apiMessages[lastUserIdx]['content'];
      final content = <Map<String, dynamic>>[
        {
          'type': 'text',
          'text': lastText is String ? lastText : '',
        },
        for (final src in images)
          {
            'type': 'image_url',
            'image_url': {'url': src},
          },
      ];
      apiMessages[lastUserIdx] = {'role': 'user', 'content': content};
    }
  }
  return apiMessages;
}
