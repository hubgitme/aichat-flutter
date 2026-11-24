import 'package:aichat/models.dart';
import 'package:aichat/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractUrls', () {
    test('extracts first URL and strips trailing punctuation', () {
      expect(
        extractUrls('ببین https://example.com/page. و این هم http://x.ir/a?b=1،'),
        ['https://example.com/page', 'http://x.ir/a?b=1'],
      );
    });

    test('dedupes and ignores non-URLs', () {
      expect(
        extractUrls('https://a.ir https://a.ir متن بدون لینک'),
        ['https://a.ir'],
      );
      expect(extractUrls('سلام دنیا'), isEmpty);
    });
  });

  group('isLongCode', () {
    test('thresholds: 1200 chars or 30 lines', () {
      expect(isLongCode('x' * 1199), isFalse);
      expect(isLongCode('x' * 1200), isTrue);
      expect(isLongCode(List.filled(29, 'line').join('\n')), isFalse);
      expect(isLongCode(List.filled(30, 'line').join('\n')), isTrue);
    });
  });

  group('filenameForLang', () {
    test('stable meaningful names', () {
      expect(filenameForLang('python'), 'script.py');
      expect(filenameForLang('javascript'), 'script.js');
      expect(filenameForLang('html'), 'index.html');
      expect(filenameForLang('css'), 'style.css');
      expect(filenameForLang('json'), 'data.json');
      expect(filenameForLang('rust'), 'code.txt');
      expect(filenameForLang(''), 'code.txt');
    });
  });

  group('trimHistory', () {
    List<Map<String, dynamic>> msgs(int n) => [
          for (var i = 0; i < n; i++)
            {'role': i.isEven ? 'user' : 'assistant', 'content': 'm$i'},
        ];

    test('keeps newest within limits', () {
      final r = trimHistory(msgs(50));
      expect(r.messages.length, 40);
      expect(r.dropped, 10);
      expect(r.messages.last['content'], 'm49');
    });

    test('never starts with assistant', () {
      final r = trimHistory([
        {'role': 'assistant', 'content': 'a'},
        {'role': 'user', 'content': 'b'},
      ], maxMessages: 1);
      expect(r.messages.first['role'], 'user');
    });

    test('char cap drops old messages', () {
      final r = trimHistory([
        {'role': 'user', 'content': 'x' * 50000},
        {'role': 'assistant', 'content': 'y' * 50000},
        {'role': 'user', 'content': 'z'},
      ]);
      expect(r.messages.last['content'], 'z');
      expect(r.messages.length, 1);
      expect(r.dropped, 2);
    });
  });

  group('context builders', () {
    test('search context lists results with numbers', () {
      final ctx = buildSearchContextMessage('گربه', [
        const Source(title: 'T', url: 'https://t.ir', snippet: 'S'),
      ]);
      expect(ctx, contains('[1] T'));
      expect(ctx, contains('https://t.ir'));
    });

    test('search context handles no results', () {
      final ctx = buildSearchContextMessage('گربه', []);
      expect(ctx, contains('نتیجه‌ای نداشت'));
    });

    test('url context includes text and truncation note', () {
      final ctx = buildUrlContextMessage('https://x.ir', {
        'url': 'https://x.ir',
        'title': 'عنوان',
        'text': 'متن صفحه',
        'truncated': true,
      });
      expect(ctx, contains('متن صفحه'));
      expect(ctx, contains('۲۰٬۰۰۰ کاراکتر'));
      expect(ctx, contains('از خودت اضافه نکن'));
    });

    test('url error context forbids inventing', () {
      final ctx =
          buildUrlErrorContextMessage('https://x.ir', 'خطای 404');
      expect(ctx, contains('نتوانستی صفحه را بخوانی'));
      expect(ctx, contains('از خودت نساز'));
    });
  });

  group('buildApiMessages', () {
    test('skips generated images, errors and empty messages', () {
      final conv = Conversation(
        id: 'c1',
        createdAt: 1,
        updatedAt: 2,
        messages: [
          ChatMessage(role: 'user', content: 'سلام'),
          ChatMessage(
              role: 'assistant', content: '', generatedImage: true),
          ChatMessage(role: 'assistant', content: 'خطا', error: true),
          ChatMessage(role: 'assistant', content: 'سلام!'),
        ],
      );
      final msgs = buildApiMessages(conv);
      // system + user + assistant
      expect(msgs.length, 3);
      expect(msgs[1]['content'], 'سلام');
      expect(msgs[2]['content'], 'سلام!');
    });

    test('system context appended after history', () {
      final conv = Conversation(
        id: 'c1',
        createdAt: 1,
        updatedAt: 2,
        messages: [ChatMessage(role: 'user', content: '؟')],
      );
      final msgs = buildApiMessages(conv, context: 'CTX');
      expect(msgs.last['role'], 'system');
      expect(msgs.last['content'], 'CTX');
    });
  });
}
