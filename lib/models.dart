// مدل‌های دادهٔ ای‌چت — هم‌ارز ساختار JSON نسخهٔ وب (js/db.js و js/sync.js).
// فیلدها عمداً همان نام‌های نسخهٔ وب را دارند تا خروجی/ورودی JSON و
// همگام‌سازی با وب سازگار بماند.

/// یک منبعِ جست‌وجوی وب (نتیجهٔ /search-web).
class Source {
  final String title;
  final String url;
  final String snippet;

  const Source({this.title = '', this.url = '', this.snippet = ''});

  factory Source.fromJson(Map<String, dynamic> json) => Source(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        snippet: json['snippet'] as String? ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'title': title, 'url': url, 'snippet': snippet};
}

/// یک پیام در گفت‌وگو. `content` متنِ پیام است؛ `images` عکس‌های پیوستی
/// (data URL یا لینک)؛ `apiContent` در صورت وجود به‌جای content به مدل می‌رسد.
class ChatMessage {
  final String role; // 'user' | 'assistant'
  String content;
  String? apiContent;
  List<String>? images;
  List<String>? docNames;
  List<Source>? sources;
  bool error;
  bool generatedImage;
  bool generatedVideo;
  String? videoUrl;
  bool imagesOmitted;

  ChatMessage({
    required this.role,
    this.content = '',
    this.apiContent,
    this.images,
    this.docNames,
    this.sources,
    this.error = false,
    this.generatedImage = false,
    this.generatedVideo = false,
    this.videoUrl,
    this.imagesOmitted = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final images = json['images'];
    final sources = json['sources'];
    final docNames = json['docNames'];
    return ChatMessage(
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      apiContent: json['apiContent'] as String?,
      images: images is List
          ? images.whereType<String>().toList()
          : null,
      docNames: docNames is List
          ? docNames.whereType<String>().toList()
          : null,
      sources: sources is List
          ? sources
              .whereType<Map<String, dynamic>>()
              .map(Source.fromJson)
              .toList()
          : null,
      error: json['error'] == true,
      generatedImage: json['generatedImage'] == true,
      generatedVideo: json['generatedVideo'] == true,
      videoUrl: json['videoUrl'] as String?,
      imagesOmitted: json['imagesOmitted'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'role': role, 'content': content};
    if (apiContent != null) m['apiContent'] = apiContent;
    if (images != null) m['images'] = images;
    if (docNames != null) m['docNames'] = docNames;
    if (sources != null) {
      m['sources'] = sources!.map((s) => s.toJson()).toList();
    }
    if (error) m['error'] = true;
    if (generatedImage) m['generatedImage'] = true;
    if (generatedVideo) m['generatedVideo'] = true;
    if (videoUrl != null) m['videoUrl'] = videoUrl;
    if (imagesOmitted) m['imagesOmitted'] = true;
    return m;
  }

  ChatMessage copy() => ChatMessage.fromJson(toJson());
}

/// یک گفت‌وگو.
class Conversation {
  final String id;
  String title;
  int createdAt;
  int updatedAt;
  List<ChatMessage> messages;

  Conversation({
    required this.id,
    this.title = '',
    required this.createdAt,
    required this.updatedAt,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final msgs = json['messages'];
    return Conversation(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
      messages: msgs is List
          ? msgs
              .whereType<Map<String, dynamic>>()
              .map(ChatMessage.fromJson)
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  /// نسخهٔ قابل‌ارسال برای همگام‌سازی: عکس‌های data: حذف و با
  /// imagesOmitted علامت‌گذاری می‌شوند (همان js/sync.js).
  Map<String, dynamic> toSyncPayload() {
    final msgs = messages.map((m) {
      final out = Map<String, dynamic>.from(m.toJson());
      var omitted = m.imagesOmitted;
      final imgs = m.images;
      if (imgs != null) {
        final keep =
            imgs.where((s) => !s.startsWith('data:')).toList();
        if (keep.length != imgs.length) omitted = true;
        if (keep.isNotEmpty) {
          out['images'] = keep;
        } else {
          out.remove('images');
        }
      }
      if (omitted) {
        out['imagesOmitted'] = true;
      } else {
        out.remove('imagesOmitted');
      }
      return out;
    }).toList();
    return {
      'id': id,
      'title': title,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'messages': msgs,
    };
  }
}

/// پاک‌سازیِ گفت‌وگوی دریافتی از همگام‌سازی (همان sanitizeConversation در
/// js/sync.js) — ساختار و فیلدها بررسی می‌شوند.
Conversation sanitizeConversation(Map<String, dynamic> obj, String expectedId) {
  if (obj['id'] != expectedId || obj['messages'] is! List) {
    throw const FormatException('ساختار گفت‌وگوی دریافتی نامعتبر است.');
  }
  final msgs = <ChatMessage>[];
  for (final raw in obj['messages'] as List) {
    if (raw is! Map<String, dynamic>) continue;
    final role = raw['role'];
    if (role != 'user' && role != 'assistant') continue;
    final m = ChatMessage.fromJson(raw);
    // fromJson رشته‌های غیرمعتبر را رد نمی‌کند؛ role را دوباره چک می‌کنیم.
    if (m.role != 'user' && m.role != 'assistant') continue;
    msgs.add(m);
  }
  return Conversation(
    id: expectedId,
    title: (obj['title'] as String? ?? '').length > 200
        ? (obj['title'] as String).substring(0, 200)
        : (obj['title'] as String? ?? ''),
    createdAt: (obj['created_at'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch,
    updatedAt: (obj['updated_at'] as num?)?.toInt() ?? 0,
    messages: msgs,
  );
}

/// اگر نسخهٔ دریافتی عکس‌هایش را همگام نکرده بود (imagesOmitted)، عکس‌های
/// محلیِ همان پیام حفظ می‌شوند (همان mergeOmittedImages در js/sync.js).
Conversation mergeOmittedImages(Conversation remote, Conversation? local) {
  if (local == null) return remote;
  for (var i = 0; i < remote.messages.length; i++) {
    final m = remote.messages[i];
    if (!m.imagesOmitted) continue;
    if (i >= local.messages.length) continue;
    final lm = local.messages[i];
    if (lm.role == m.role && lm.images != null && lm.images!.isNotEmpty) {
      m.images = lm.images;
      m.imagesOmitted = false;
    }
  }
  return remote;
}
