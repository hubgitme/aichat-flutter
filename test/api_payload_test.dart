import 'package:aichat/api.dart';
import 'package:aichat/models.dart';
import 'package:aichat/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildChatRequestBody', () {
    test('includes messages, provider, model and key', () {
      final body = buildChatRequestBody(
        messages: [
          {'role': 'user', 'content': 'سلام'},
        ],
        providerUrl: 'https://example.com/v1',
        model: 'm1',
        apiKey: 'k1',
      );
      expect(body['provider_url'], 'https://example.com/v1');
      expect(body['model'], 'm1');
      expect(body['api_key'], 'k1');
      expect((body['messages'] as List).length, 1);
    });
  });

  group('buildImageRequestBody', () {
    test('generations omits empty model/key and source', () {
      final body = buildImageRequestBody(
        prompt: 'a cat',
        providerUrl: 'https://img.example.com',
        endpointType: 'generations',
      );
      expect(body['prompt'], 'a cat');
      expect(body['endpoint_type'], 'generations');
      expect(body.containsKey('model'), isFalse);
      expect(body.containsKey('source_image'), isFalse);
    });

    test('edits_json includes source image data URL', () {
      final body = buildImageRequestBody(
        prompt: 'make it cartoon',
        providerUrl: 'https://token.example.com/v1',
        model: 'sensenova-u1.5-lite',
        apiKey: 'sk-x',
        endpointType: 'edits_json',
        sourceImageDataUrl: 'data:image/png;base64,AAAA',
      );
      expect(body['endpoint_type'], 'edits_json');
      expect(body['source_image'], 'data:image/png;base64,AAAA');
      expect(body['model'], 'sensenova-u1.5-lite');
    });

    test('simple_get includes url pattern', () {
      final body = buildImageRequestBody(
        prompt: 'a cat',
        providerUrl: 'https://img.example.com',
        endpointType: 'simple_get',
        urlPattern: '/prompt/{prompt}?model={model}',
      );
      expect(body['url_pattern'], '/prompt/{prompt}?model={model}');
    });
  });

  group('buildVideoRequestBody', () {
    test('includes duration and pattern', () {
      final body = buildVideoRequestBody(
        prompt: 'a cat walking',
        providerUrl: 'https://vid.example.com',
        model: 'vm',
        apiKey: 'k',
        duration: '5',
        urlPattern: '/video/{prompt}?model={model}&duration={duration}&key={key}',
      );
      expect(body['duration'], '5');
      expect(body['url_pattern'], contains('{duration}'));
    });
  });

  group('parseSseBuffer', () {
    test('parses delta events and [DONE]', () {
      const buf =
          'data: {"choices":[{"delta":{"content":"سلام"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"!"}}]}\n\n'
          'data: [DONE]\n\n';
      final r = parseSseBuffer(buf);
      expect(r.deltas, ['سلام', '!']);
      expect(r.errors, isEmpty);
      expect(r.remainder, '');
    });

    test('keeps incomplete trailing chunk as remainder', () {
      const buf = 'data: {"choices":[{"delta":{"content":"س';
      final r = parseSseBuffer(buf);
      expect(r.deltas, isEmpty);
      expect(r.remainder, buf);
      final r2 = parseSseBuffer('${r.remainder}لام"}}]}\n\n');
      expect(r2.deltas, ['سلام']);
    });

    test('message.content fallback and error events', () {
      const buf =
          'data: {"choices":[{"message":{"content":"کامل"}}]}\n\n'
          'data: {"error":"bad key"}\n\n';
      final r = parseSseBuffer(buf);
      expect(r.deltas, ['کامل']);
      expect(r.errors, ['bad key']);
    });

    test('ignores non-data lines and broken JSON', () {
      const buf = ': ping\n\ndata: not-json\n\ndata: {"choices":[]}\n\n';
      final r = parseSseBuffer(buf);
      expect(r.deltas, isEmpty);
      expect(r.errors, isEmpty);
    });
  });

  group('buildApiMessages (via utils)', () {
    test('attaches images to last user message', () {
      final conv = Conversation(
        id: 'c1',
        createdAt: 1,
        updatedAt: 2,
        messages: [
          ChatMessage(role: 'user', content: 'این چیه؟'),
        ],
      );
      final msgs = buildApiMessages(conv,
          images: ['data:image/png;base64,AAAA']);
      final last = msgs.last;
      expect(last['role'], 'user');
      final content = last['content'] as List;
      expect(content.first['type'], 'text');
      expect(content.first['text'], 'این چیه؟');
      expect(content[1]['type'], 'image_url');
      expect(content[1]['image_url']['url'], 'data:image/png;base64,AAAA');
    });
  });
}
