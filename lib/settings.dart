// تنظیمات ای‌چت — در SharedPreferences ذخیره می‌شوند.
// هیچ مقدار پیش‌فرضی برای پروایدر، مدل یا کلید وجود ندارد: کاربر همه را
// خودش وارد می‌کند. آدرس بک‌اند هم خالی است تا کاربر دیپلوی Vercel خودش را
// وارد کند.

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

class AppSettings {
  // اتصال
  String backendUrl;
  // مدل چت
  String chatProviderUrl;
  String chatModel;
  String chatApiKey;
  // تصویر
  String imageProviderUrl;
  String imageModel;
  String imageApiKey;
  ImageEndpointType imageEndpointType;
  String imageUrlPattern;
  // ویدیو
  String videoProviderUrl;
  String videoModel;
  String videoApiKey;
  String videoDuration;
  String videoUrlPattern;
  // سینک
  String syncCode;
  bool autoSync;

  AppSettings({
    this.backendUrl = '',
    this.chatProviderUrl = '',
    this.chatModel = '',
    this.chatApiKey = '',
    this.imageProviderUrl = '',
    this.imageModel = '',
    this.imageApiKey = '',
    this.imageEndpointType = ImageEndpointType.generations,
    this.imageUrlPattern = '',
    this.videoProviderUrl = '',
    this.videoModel = '',
    this.videoApiKey = '',
    this.videoDuration = '4',
    this.videoUrlPattern = '',
    this.syncCode = '',
    this.autoSync = false,
  });

  static const _p = 'aichat_';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    String s(String k) => prefs.getString('$_p$k') ?? '';
    return AppSettings(
      backendUrl: s('backend_url'),
      chatProviderUrl: s('chat_provider_url'),
      chatModel: s('chat_model'),
      chatApiKey: s('chat_api_key'),
      imageProviderUrl: s('image_provider_url'),
      imageModel: s('image_model'),
      imageApiKey: s('image_api_key'),
      imageEndpointType:
          ImageEndpointTypeLabel.fromValue(s('image_endpoint_type')),
      imageUrlPattern: s('image_url_pattern'),
      videoProviderUrl: s('video_provider_url'),
      videoModel: s('video_model'),
      videoApiKey: s('video_api_key'),
      videoDuration: s('video_duration').isEmpty ? '4' : s('video_duration'),
      videoUrlPattern: s('video_url_pattern'),
      syncCode: s('sync_code'),
      autoSync: prefs.getBool('${_p}auto_sync') ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    Future<void> put(String k, String v) => prefs.setString('$_p$k', v);
    await put('backend_url', backendUrl);
    await put('chat_provider_url', chatProviderUrl);
    await put('chat_model', chatModel);
    await put('chat_api_key', chatApiKey);
    await put('image_provider_url', imageProviderUrl);
    await put('image_model', imageModel);
    await put('image_api_key', imageApiKey);
    await put('image_endpoint_type', imageEndpointType.value);
    await put('image_url_pattern', imageUrlPattern);
    await put('video_provider_url', videoProviderUrl);
    await put('video_model', videoModel);
    await put('video_api_key', videoApiKey);
    await put('video_duration', videoDuration);
    await put('video_url_pattern', videoUrlPattern);
    await put('sync_code', syncCode);
    await prefs.setBool('${_p}auto_sync', autoSync);
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
