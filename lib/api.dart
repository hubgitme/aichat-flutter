// کلاینتِ بک‌اندِ Flask ای‌چت — همان قراردادِ api/index.py.
// همهٔ تماس‌ها با آدرس بک‌اندِ کاربر (Vercel) انجام می‌شوند؛ هیچ آدرسی
// هاردکد نشده است.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'settings.dart';

/// خطای قابل‌نمایش به کاربر؛ `retryable` یعنی تلاش دوباره ارزش دارد.
class ApiException implements Exception {
  final String message;
  final bool retryable;
  const ApiException(this.message, {this.retryable = false});
  @override
  String toString() => message;
}

String _stripBase(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');

/// بدنهٔ درخواست چت (برای تست هم استفاده می‌شود).
Map<String, dynamic> buildChatRequestBody({
  required List<Map<String, dynamic>> messages,
  required String providerUrl,
  required String model,
  required String apiKey,
}) =>
    {
      'messages': messages,
      'provider_url': providerUrl,
      'model': model,
      'api_key': apiKey,
    };

/// بدنهٔ درخواست تصویر.
Map<String, dynamic> buildImageRequestBody({
  required String prompt,
  required String providerUrl,
  String? model,
  String? apiKey,
  required String endpointType,
  String? sourceImageDataUrl,
  String? urlPattern,
}) {
  final body = <String, dynamic>{
    'prompt': prompt,
    'provider_url': providerUrl,
    'endpoint_type': endpointType,
  };
  if (model != null && model.isNotEmpty) body['model'] = model;
  if (apiKey != null && apiKey.isNotEmpty) body['api_key'] = apiKey;
  if (sourceImageDataUrl != null) body['source_image'] = sourceImageDataUrl;
  if (urlPattern != null && urlPattern.isNotEmpty) {
    body['url_pattern'] = urlPattern;
  }
  return body;
}

/// بدنهٔ درخواست ویدیو.
Map<String, dynamic> buildVideoRequestBody({
  required String prompt,
  required String providerUrl,
  String? model,
  String? apiKey,
  required String duration,
  String? urlPattern,
}) {
  final body = <String, dynamic>{
    'prompt': prompt,
    'provider_url': providerUrl,
    'duration': duration,
  };
  if (model != null && model.isNotEmpty) body['model'] = model;
  if (apiKey != null && apiKey.isNotEmpty) body['api_key'] = apiKey;
  if (urlPattern != null && urlPattern.isNotEmpty) {
    body['url_pattern'] = urlPattern;
  }
  return body;
}

/// نتیجهٔ پارسِ یک تکهٔ بافرِ SSE: رویدادها + باقی‌ماندهٔ ناقص.
class SseParseResult {
  final List<String> deltas;
  final List<String> errors;
  final String remainder;
  const SseParseResult(this.deltas, this.errors, this.remainder);
}

/// پارسِ رویدادهای `data: {...}` از بافر (همان منطق js/chat.js).
SseParseResult parseSseBuffer(String buffer) {
  final deltas = <String>[];
  final errors = <String>[];
  final parts = buffer.split('\n\n');
  final remainder = parts.removeLast();
  for (final part in parts) {
    final line = part.trim();
    if (!line.startsWith('data:')) continue;
    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') continue;
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      continue; // chunk ناقص/غیر JSON — نادیده می‌گیریم
    }
    if (json['error'] != null) {
      errors.add(json['error'].toString());
      continue;
    }
    final choices = json['choices'];
    var delta = '';
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final d = first['delta'];
        final m = first['message'];
        if (d is Map && d['content'] is String) {
          delta = d['content'] as String;
        } else if (m is Map && m['content'] is String) {
          delta = m['content'] as String;
        }
      }
    }
    if (delta.isNotEmpty) deltas.add(delta);
  }
  return SseParseResult(deltas, errors, remainder);
}

String _providerMessage(String? details) {
  if (details == null || details.isEmpty) return '';
  try {
    final parsed = jsonDecode(details);
    if (parsed is Map) {
      final err = parsed['error'];
      if (err is Map && err['message'] is String) {
        return err['message'] as String;
      }
      if (parsed['message'] is String) return parsed['message'] as String;
    }
  } catch (_) {}
  return '';
}

class ApiClient {
  final String backendBase;
  final http.Client _client;

  ApiClient(this.backendBase, {http.Client? client})
      : _client = client ?? http.Client();

  void close() => _client.close();

  Uri _uri(String path) => Uri.parse('${_stripBase(backendBase)}$path');

  Future<Map<String, dynamic>> _postJson(
      String path, Map<String, dynamic> body) async {
    late final http.Response res;
    try {
      res = await _client
          .post(_uri(path),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw const ApiException('پروایدر دیر پاسخ داد', retryable: true);
    } on SocketException {
      throw const ApiException('خطای شبکه در ارتباط با بک‌اند',
          retryable: true);
    } on HttpException {
      throw const ApiException('خطای شبکه در ارتباط با بک‌اند',
          retryable: true);
    }
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final retryable = [429, 502, 503, 504].contains(res.statusCode);
      throw ApiException(
          (data['error'] as String?)?.isNotEmpty == true
              ? data['error'] as String
              : 'خطای سرور (${res.statusCode})',
          retryable: retryable);
    }
    return data;
  }

  /// استریمِ چت با retry (همان js/chat.js): تا ۳ تلاش روی خطاهای گذرا،
  /// فقط وقتی هنوز متنی دریافت نشده. `onToken` با هر دلتا صدا زده می‌شود
  /// و مقدار برگشتی متنِ کامل است. توقف با `isCancelled` انجام می‌شود:
  /// وقتی true شد، متنِ ناقصِ تاکنون برگردانده می‌شود و retry نمی‌شود.
  Future<String> streamChat({
    required List<Map<String, dynamic>> messages,
    required AppSettings settings,
    required void Function(String delta, String full) onToken,
    bool Function()? isCancelled,
    http.Client Function()? clientFactory,
  }) async {
    var fullText = '';
    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      if (isCancelled?.call() == true) return fullText;
      final client = clientFactory?.call() ?? http.Client();
      try {
        final request = http.Request('POST', _uri('/chat-ai'))
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(buildChatRequestBody(
            messages: messages,
            providerUrl: settings.chatProviderUrl,
            model: settings.chatModel,
            apiKey: settings.chatApiKey,
          ));
        final streamed = await client.send(request);
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          final body = await streamed.stream.bytesToString();
          var detail = '';
          try {
            detail =
                (jsonDecode(body) as Map)['error'] as String? ?? '';
          } catch (_) {}
          final retryable =
              [429, 502, 503, 504].contains(streamed.statusCode);
          throw ApiException(
              detail.isNotEmpty
                  ? detail
                  : 'خطای سرور (${streamed.statusCode})',
              retryable: retryable);
        }
        var buffer = '';
        await for (final chunk
            in streamed.stream.transform(utf8.decoder)) {
          if (isCancelled?.call() == true) {
            client.close();
            return fullText;
          }
          buffer += chunk;
          final parsed = parseSseBuffer(buffer);
          buffer = parsed.remainder;
          for (final err in parsed.errors) {
            throw ApiException(err);
          }
          for (final delta in parsed.deltas) {
            fullText += delta;
            onToken(delta, fullText);
          }
        }
        if (buffer.trim().isNotEmpty) {
          final parsed = parseSseBuffer('$buffer\n\n');
          for (final err in parsed.errors) {
            throw ApiException(err);
          }
          for (final delta in parsed.deltas) {
            fullText += delta;
            onToken(delta, fullText);
          }
        }
        client.close();
        return fullText;
      } on ApiException catch (e) {
        client.close();
        if (isCancelled?.call() == true) return fullText;
        if (e.retryable && fullText.isEmpty && attempt < maxRetries - 1) {
          await Future.delayed(
              Duration(milliseconds: 1000 * (attempt + 1)));
          continue;
        }
        rethrow;
      } on http.ClientException {
        client.close();
        if (isCancelled?.call() == true) return fullText;
        if (fullText.isEmpty && attempt < maxRetries - 1) {
          await Future.delayed(
              Duration(milliseconds: 1000 * (attempt + 1)));
          continue;
        }
        throw const ApiException('خطای شبکه در ارتباط با بک‌اند',
            retryable: true);
      }
    }
    return fullText;
  }

  /// جست‌وجوی وب — برمی‌گرداند لیست منابع.
  Future<List<Source>> searchWeb(String query) async {
    final data = await _postJson('/search-web', {'query': query});
    final results = data['results'];
    if (results is List) {
      return results
          .whereType<Map<String, dynamic>>()
          .map(Source.fromJson)
          .toList();
    }
    throw ApiException(
        (data['error'] as String?) ?? 'خطا در جست‌وجوی وب.');
  }

  /// خواندن یک صفحهٔ وب — {url, title, text, truncated}.
  Future<Map<String, dynamic>> fetchUrl(String url) async {
    final data = await _postJson('/fetch-url', {'url': url});
    if (data['error'] != null) {
      throw ApiException(data['error'] as String);
    }
    return data;
  }

  /// تولید/ویرایش تصویر — برمی‌گرداند لیست data URL یا لینک عکس.
  Future<List<String>> generateImage({
    required String prompt,
    required AppSettings settings,
    String? sourceImageDataUrl,
  }) async {
    final data = await _postJson(
        '/generate-image',
        buildImageRequestBody(
          prompt: prompt,
          providerUrl: settings.imageProviderUrl,
          model: settings.imageModel,
          apiKey: settings.imageApiKey,
          endpointType: settings.imageEndpointType.value,
          sourceImageDataUrl: sourceImageDataUrl,
          urlPattern: settings.imageUrlPattern,
        ));
    if (data['success'] != true) {
      final msg = _providerMessage(data['details'] as String?);
      throw ApiException(msg.isNotEmpty
          ? msg
          : (data['error'] as String?) ?? 'خطا در تولید تصویر.');
    }
    final images = data['images'];
    if (images is List) return images.whereType<String>().toList();
    return const [];
  }

  /// ساخت ویدیو — برمی‌گرداند آدرس نهایی ویدیو.
  Future<String> generateVideo({
    required String prompt,
    required AppSettings settings,
  }) async {
    final data = await _postJson(
        '/generate-video',
        buildVideoRequestBody(
          prompt: prompt,
          providerUrl: settings.videoProviderUrl,
          model: settings.videoModel,
          apiKey: settings.videoApiKey,
          duration: settings.videoDuration,
          urlPattern: settings.videoUrlPattern,
        ));
    if (data['success'] != true) {
      throw ApiException(
          (data['error'] as String?) ?? 'خطا در ساخت ویدیو.');
    }
    return (data['video_url'] as String?) ?? '';
  }

  /// تماسِ خام با /sync: {sync_id, action, ...payload}.
  Future<Map<String, dynamic>> syncCall(
      String syncId, String action, Map<String, dynamic> payload) async {
    return _postJson('/sync', {
      'sync_id': syncId,
      'action': action,
      ...payload,
    });
  }
}
