// تنظیمات ای‌چت — در SharedPreferences ذخیره می‌شوند.
// مدلِ ثبت‌نام مثل نسخهٔ وب (js/config.js):
// - رجیستری پروایدرها: {شناسه، نام، آدرس پایه، مدل‌ها}
// - رجیستری کلیدها: {برچسب، کلید}
// - برای هر حالت (چت/تصویر/ویدیو) فقط «کدام پروایدر|مدل» و «کدام کلید»
//   انتخاب می‌شود؛ آدرس و مدل و کلیدِ مؤثر از روی رجیستری خوانده می‌شوند.
// هیچ مقدار پیش‌فرضی برای پروایدر، مدل یا کلید وجود ندارد: کاربر همه را
// خودش وارد می‌کند. آدرس بک‌اند هم خالی است تا کاربر دیپلوی Vercel خودش را
// وارد کند.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// نوع اندپوینت تصویر (همان مقادیر نسخهٔ وب).
enum ImageEndpointType { generations, edits, editsJson, simpleGet }

extension ImageEndpointTypeLabel on ImageEndpointType {
  String get value {
    switch (this) {
      case ImageEndpointType.generations:
        return 'generations';
      case ImageEndpointType.edits:
        return 'edits';
      case ImageEndpointType.editsJson:
        return 'edits_json';
      case ImageEndpointType.simpleGet:
        return 'simple_get';
    }
  }

  String get label {
    switch (this) {
      case ImageEndpointType.generations:
        return 'تولید عادی (images/generations)';
      case ImageEndpointType.edits:
        return 'ویرایش عکس (images/edits)';
      case ImageEndpointType.editsJson:
        return 'ویرایش عکس JSON (images/edits — SenseNova)';
      case ImageEndpointType.simpleGet:
        return 'ساده GET (قابل‌تنظیم) — بدون نیاز به کلید';
    }
  }

  static ImageEndpointType fromValue(String? v) {
    switch (v) {
      case 'edits':
        return ImageEndpointType.edits;
      case 'edits_json':
        return ImageEndpointType.editsJson;
      case 'simple_get':
        return ImageEndpointType.simpleGet;
      case 'generations':
      default:
        return ImageEndpointType.generations;
    }
  }
}

/// یک پروایدرِ ثبت‌شده: نام + آدرس پایه + مدل‌ها.
class ProviderEntry {
  final String id;
  String name;
  String baseUrl;
  List<String> models;

  ProviderEntry({
    required this.id,
    required this.name,
    required this.baseUrl,
    List<String>? models,
  }) : models = models ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': baseUrl,
        'models': models,
      };

  static ProviderEntry fromJson(Map<String, dynamic> json) {
    final models = json['models'];
    return ProviderEntry(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      baseUrl: (json['url'] as String?) ?? '',
      models: models is List ? models.whereType<String>().toList() : [],
    );
  }
}

/// یک کلید API ثبت‌شده.
class ApiKeyEntry {
  final String label;
  final String key;

  const ApiKeyEntry({required this.label, required this.key});

  Map<String, dynamic> toJson() => {'label': label, 'key': key};

  static ApiKeyEntry fromJson(Map<String, dynamic> json) {
    return ApiKeyEntry(
      label: (json['label'] as String?) ?? '',
      key: (json['key'] as String?) ?? '',
    );
  }
}

/// یک گزینهٔ «پروایدر — مدل» برای دراپ‌داون‌ها.
class ProviderModelOption {
  final String value; // «providerId|model»
  final String label; // «نام (مدل)»
  const ProviderModelOption(this.value, this.label);
}

class AppSettings {
  // اتصال
  String backendUrl;
  // رجیستری‌ها
  List<ProviderEntry> providers;
  List<ApiKeyEntry> apiKeys;
  // انتخاب‌ها (مثل نسخهٔ وب): «providerId|model» و مقدارِ کلید.
  String chatProviderModel;
  String chatKey;
  String imageProviderModel;
  String imageKey;
  ImageEndpointType imageEndpointType;
  String imageUrlPattern;
  String videoProviderModel;
  String videoKey;
  String videoDuration;
  String videoUrlPattern;
  // سینک
  String syncCode;
  bool autoSync;

  AppSettings({
    this.backendUrl = '',
    List<ProviderEntry>? providers,
    List<ApiKeyEntry>? apiKeys,
    this.chatProviderModel = '',
    this.chatKey = '',
    this.imageProviderModel = '',
    this.imageKey = '',
    this.imageEndpointType = ImageEndpointType.generations,
    this.imageUrlPattern = '',
    this.videoProviderModel = '',
    this.videoKey = '',
    this.videoDuration = '4',
    this.videoUrlPattern = '',
    this.syncCode = '',
    this.autoSync = false,
  })  : providers = providers ?? [],
        apiKeys = apiKeys ?? [];

  static const _p = 'aichat_';

  // --- رجیستری پروایدرها ---

  ProviderEntry? providerById(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  static String _newProviderId() =>
      'p${DateTime.now().millisecondsSinceEpoch}';

  /// افزودن پروایدر یا ادغام مدل‌ها در پروایدرِ هم‌نام (مثل نسخهٔ وب).
  ProviderEntry addProvider(String name, String baseUrl, List<String> models) {
    final norm = name.trim().toLowerCase();
    ProviderEntry? existing;
    for (final p in providers) {
      if (p.name.trim().toLowerCase() == norm) existing = p;
    }
    final entry = existing ??
        ProviderEntry(
          id: _newProviderId(),
          name: name.trim(),
          baseUrl: baseUrl.trim(),
        );
    if (existing == null) providers.add(entry);
    entry.baseUrl = baseUrl.trim();
    for (final m in models) {
      final model = m.trim();
      if (model.isNotEmpty && !entry.models.contains(model)) {
        entry.models.add(model);
      }
    }
    return entry;
  }

  void deleteProvider(String id) {
    providers.removeWhere((p) => p.id == id);
  }

  /// حذف یک مدل؛ اگر آخرین مدلِ پروایدر بود، خودِ پروایدر هم حذف می‌شود
  /// (مثل نسخهٔ وب).
  void deleteModel(String providerId, String model) {
    final p = providerById(providerId);
    if (p == null) return;
    p.models.remove(model);
    if (p.models.isEmpty) deleteProvider(providerId);
  }

  /// به‌روزرسانی آدرس پایهٔ یک پروایدر. false یعنی آدرس نامعتبر است.
  bool updateProviderUrl(String id, String url) {
    final p = providerById(id);
    if (p == null) return false;
    final u = url.trim();
    if (!u.toLowerCase().startsWith('https://')) return false;
    p.baseUrl = u;
    return true;
  }

  // --- رجیستری کلیدها ---

  /// ثبت کلید؛ کلیدِ تکراری با برچسبِ جدید جایگزین می‌شود (بدون تکرار).
  void addApiKey(String label, String key) {
    final l = label.trim();
    final k = key.trim();
    if (l.isEmpty || k.isEmpty) return;
    apiKeys.removeWhere((e) => e.key == k);
    apiKeys.add(ApiKeyEntry(label: l, key: k));
  }

  void deleteApiKey(String key) {
    apiKeys.removeWhere((e) => e.key == key);
  }

  // --- گزینه‌های دراپ‌داون ---

  List<ProviderModelOption> get providerModelOptions {
    final items = <ProviderModelOption>[];
    for (final p in providers) {
      for (final m in p.models) {
        items.add(ProviderModelOption('${p.id}|$m', '${p.name} ($m)'));
      }
    }
    return items;
  }

  // --- مقادیرِ مؤثر (برای api.dart و صفحهٔ اصلی) ---

  String _providerUrlFor(String selection) {
    final idx = selection.indexOf('|');
    if (idx < 0) return '';
    return providerById(selection.substring(0, idx))?.baseUrl ?? '';
  }

  String _modelFor(String selection) {
    final idx = selection.indexOf('|');
    if (idx < 0) return '';
    return selection.substring(idx + 1);
  }

  bool _selectionExists(String selection) {
    final idx = selection.indexOf('|');
    if (idx < 0) return false;
    final p = providerById(selection.substring(0, idx));
    return p != null && p.models.contains(selection.substring(idx + 1));
  }

  String get chatProviderUrl => _providerUrlFor(chatProviderModel);
  String get chatModel => _modelFor(chatProviderModel);
  String get chatApiKey => chatKey;
  String get imageProviderUrl => _providerUrlFor(imageProviderModel);
  String get imageModel => _modelFor(imageProviderModel);
  String get imageApiKey => imageKey;
  String get videoProviderUrl => _providerUrlFor(videoProviderModel);
  String get videoModel => _modelFor(videoProviderModel);
  String get videoApiKey => videoKey;

  // --- ذخیره/بارگذاری ---

  static List<ProviderEntry> _readProviders(SharedPreferences prefs) {
    final raw = prefs.getString('${_p}providers_json');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(ProviderEntry.fromJson)
            .where((p) => p.id.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static List<ApiKeyEntry> _readKeys(SharedPreferences prefs) {
    final raw = prefs.getString('${_p}api_keys_json');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(ApiKeyEntry.fromJson)
            .where((k) => k.key.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    String s(String k) => prefs.getString('$_p$k') ?? '';
    final settings = AppSettings(
      backendUrl: s('backend_url'),
      providers: _readProviders(prefs),
      apiKeys: _readKeys(prefs),
      chatProviderModel: s('chat_provider_model'),
      chatKey: s('chat_key'),
      imageProviderModel: s('image_provider_model'),
      imageKey: s('image_key'),
      imageEndpointType:
          ImageEndpointTypeLabel.fromValue(s('image_endpoint_type')),
      imageUrlPattern: s('image_url_pattern'),
      videoProviderModel: s('video_provider_model'),
      videoKey: s('video_key'),
      videoDuration: s('video_duration').isEmpty ? '4' : s('video_duration'),
      videoUrlPattern: s('video_url_pattern'),
      syncCode: s('sync_code'),
      autoSync: prefs.getBool('${_p}auto_sync') ?? false,
    );

    // مهاجرتِ یک‌باره از فیلدهای تکیِ نسخهٔ قبل
    // (aichat_chat_provider_url و…) به رجیستری.
    if (settings.providers.isEmpty) {
      final migrated = settings._migrateLegacy(prefs);
      if (migrated) {
        await settings._saveTo(prefs);
        for (final k in [
          'chat_provider_url',
          'chat_model',
          'chat_api_key',
          'image_provider_url',
          'image_model',
          'image_api_key',
          'video_provider_url',
          'video_model',
          'video_api_key',
        ]) {
          await prefs.remove('$_p$k');
        }
      }
    }
    return settings;
  }

  /// مهاجرتِ یک‌باره از فیلدهای تکیِ نسخهٔ قبل. true یعنی چیزی مهاجرت شد.
  bool _migrateLegacy(SharedPreferences prefs) {
    String old(String k) => prefs.getString('$_p$k') ?? '';
    var changed = false;

    String addLegacy(String url, String model) {
      if (url.trim().isEmpty) return '';
      final host = Uri.tryParse(url.trim())?.host ?? '';
      final name = host.isNotEmpty ? host : 'پروایدر قبلی';
      final entry = addProvider(
          name, url, model.trim().isEmpty ? [] : [model.trim()]);
      changed = true;
      return entry.id;
    }

    final chatUrl = old('chat_provider_url');
    final chatModel = old('chat_model');
    final oldChatKey = old('chat_api_key');
    if (chatUrl.isNotEmpty) {
      final id = addLegacy(chatUrl, chatModel);
      if (chatModel.trim().isNotEmpty && id.isNotEmpty) {
        chatProviderModel = '$id|${chatModel.trim()}';
      }
    }
    final imgUrl = old('image_provider_url');
    final imgModel = old('image_model');
    final oldImgKey = old('image_api_key');
    if (imgUrl.isNotEmpty) {
      final id = addLegacy(imgUrl, imgModel);
      if (imgModel.trim().isNotEmpty && id.isNotEmpty) {
        imageProviderModel = '$id|${imgModel.trim()}';
      }
    }
    final vidUrl = old('video_provider_url');
    final vidModel = old('video_model');
    final oldVidKey = old('video_api_key');
    if (vidUrl.isNotEmpty) {
      final id = addLegacy(vidUrl, vidModel);
      if (vidModel.trim().isNotEmpty && id.isNotEmpty) {
        videoProviderModel = '$id|${vidModel.trim()}';
      }
    }
    if (oldChatKey.trim().isNotEmpty) {
      addApiKey('کلید چت', oldChatKey);
      chatKey = oldChatKey.trim();
      changed = true;
    }
    if (oldImgKey.trim().isNotEmpty) {
      addApiKey('کلید تصویر', oldImgKey);
      imageKey = oldImgKey.trim();
      changed = true;
    }
    if (oldVidKey.trim().isNotEmpty) {
      addApiKey('کلید ویدیو', oldVidKey);
      videoKey = oldVidKey.trim();
      changed = true;
    }
    return changed;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await _saveTo(prefs);
  }

  Future<void> _saveTo(SharedPreferences prefs) async {
    Future<void> put(String k, String v) => prefs.setString('$_p$k', v);
    await put('backend_url', backendUrl);
    await put('providers_json',
        jsonEncode(providers.map((p) => p.toJson()).toList()));
    await put(
        'api_keys_json', jsonEncode(apiKeys.map((k) => k.toJson()).toList()));
    await put('chat_provider_model', chatProviderModel);
    await put('chat_key', chatKey);
    await put('image_provider_model', imageProviderModel);
    await put('image_key', imageKey);
    await put('image_endpoint_type', imageEndpointType.value);
    await put('image_url_pattern', imageUrlPattern);
    await put('video_provider_model', videoProviderModel);
    await put('video_key', videoKey);
    await put('video_duration', videoDuration);
    await put('video_url_pattern', videoUrlPattern);
    await put('sync_code', syncCode);
    await prefs.setBool('${_p}auto_sync', autoSync);
  }

  // --- پشتیبان‌گیری (مثل نسخهٔ وب) ---

  /// خروجی JSON پروایدرها و کلیدها.
  String exportConfigJson() {
    final providersMap = <String, dynamic>{};
    for (final p in providers) {
      providersMap[p.id] = {
        'name': p.name,
        'url': p.baseUrl,
        'models': p.models,
      };
    }
    return jsonEncode({
      'version': '1.0',
      'export_date': DateTime.now().toIso8601String(),
      'api_keys': apiKeys.map((k) => k.toJson()).toList(),
      ...providersMap,
    });
  }

  /// بازیابی از JSON خروجی؛ جایگزین رجیستری می‌شود. خطا پرتاب می‌کند اگر
  /// ساختار نامعتبر باشد.
  void importConfigJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ساختار فایل نامعتبر است.');
    }
    final nextProviders = <ProviderEntry>[];
    final nextKeys = <ApiKeyEntry>[];
    final keys = decoded['api_keys'];
    if (keys is List) {
      nextKeys.addAll(keys
          .whereType<Map<String, dynamic>>()
          .map(ApiKeyEntry.fromJson)
          .where((k) => k.key.isNotEmpty));
    }
    for (final entry in decoded.entries) {
      if (entry.key == 'version' ||
          entry.key == 'export_date' ||
          entry.key == 'api_keys') {
        continue;
      }
      if (entry.value is Map<String, dynamic>) {
        final map = Map<String, dynamic>.from(entry.value);
        map['id'] = entry.key;
        final p = ProviderEntry.fromJson(map);
        if (p.baseUrl.isNotEmpty) nextProviders.add(p);
      }
    }
    providers = nextProviders;
    apiKeys = nextKeys;
    if (!_selectionExists(chatProviderModel)) chatProviderModel = '';
    if (!_selectionExists(imageProviderModel)) imageProviderModel = '';
    if (!_selectionExists(videoProviderModel)) videoProviderModel = '';
    if (!apiKeys.any((k) => k.key == chatKey)) chatKey = '';
    if (!apiKeys.any((k) => k.key == imageKey)) imageKey = '';
    if (!apiKeys.any((k) => k.key == videoKey)) videoKey = '';
  }

  /// آدرس بک‌اند بدون «/» انتهایی.
  String get backendBase =>
      backendUrl.trim().replaceAll(RegExp(r'/+$'), '');

  bool get hasBackend => backendBase.isNotEmpty;
  bool get hasChatConfig =>
      chatProviderUrl.trim().isNotEmpty &&
      chatModel.trim().isNotEmpty &&
      chatApiKey.trim().isNotEmpty;
}
