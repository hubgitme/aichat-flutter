// ذخیره‌سازیِ محلیِ گفت‌وگوها و وضعیت سینک (SharedPreferences).
// هر گفت‌وگو با یک کلید جدا ذخیره می‌شود تا رشته‌های حجیم (عکس base64)
// در یک مقدارِ واحد جمع نشوند؛ فهرست idها جداگانه نگه‌داری می‌شود.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'sync_engine.dart';

class ConversationStore implements SyncLocalStore {
  static const _indexKey = 'aichat_conv_index';
  static const _convPrefix = 'aichat_conv_';
  static const _tombKey = 'aichat_sync_tombstones';
  static const _lastKey = 'aichat_sync_last';

  final SharedPreferences _prefs;

  ConversationStore(this._prefs);

  static Future<ConversationStore> load() async =>
      ConversationStore(await SharedPreferences.getInstance());

  List<String> _index() {
    final raw = _prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {}
    return [];
  }

  Future<void> _saveIndex(List<String> ids) =>
      _prefs.setString(_indexKey, jsonEncode(ids));

  @override
  Future<List<LocalMeta>> list() async {
    final metas = <LocalMeta>[];
    for (final id in _index()) {
      final conv = await get(id);
      if (conv != null) metas.add(LocalMeta(id, conv.updatedAt));
    }
    return metas;
  }

  @override
  Future<Conversation?> get(String id) async {
    final raw = _prefs.getString('$_convPrefix$id');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Conversation.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> putRaw(Conversation conv) async {
    final ids = _index();
    if (!ids.contains(conv.id)) {
      ids.add(conv.id);
      await _saveIndex(ids);
    }
    await _prefs.setString(
        '$_convPrefix${conv.id}', jsonEncode(conv.toJson()));
  }

  @override
  Future<void> remove(String id) async {
    final ids = _index()..remove(id);
    await _saveIndex(ids);
    await _prefs.remove('$_convPrefix$id');
  }

  /// همهٔ گفت‌وگوها (برای نمایش در سایدبار).
  Future<List<Conversation>> listAll() async {
    final out = <Conversation>[];
    for (final id in _index()) {
      final conv = await get(id);
      if (conv != null) out.add(conv);
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  /// خروجیِ JSON همهٔ گفت‌وگوها (همان فرمت export نسخهٔ وب نیست؛ فقط
  /// برای بکاپ/انتقال بین دستگاه‌ها با همین اپ است).
  Future<String> exportAll() async {
    final convs = await listAll();
    return jsonEncode({
      'version': '1.0',
      'export_date': DateTime.now().toIso8601String(),
      'conversations': convs.map((c) => c.toJson()).toList(),
    });
  }

  /// بازیابی از خروجیِ exportAll — جایگزینِ کاملِ گفت‌وگوهای محلی.
  Future<int> importAll(String jsonText) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ساختار فایل نامعتبر است.');
    }
    final convs = decoded['conversations'];
    if (convs is! List) {
      throw const FormatException('ساختار فایل نامعتبر است.');
    }
    var count = 0;
    for (final raw in convs) {
      if (raw is Map<String, dynamic> && raw['id'] is String) {
        await putRaw(Conversation.fromJson(raw));
        count++;
      }
    }
    return count;
  }
}

/// سنگ‌قبرهای سینک (همان js/sync-state.js).
class TombstoneStore implements SyncTombstones {
  final SharedPreferences _prefs;
  TombstoneStore(this._prefs);

  @override
  Map<String, int> get() {
    try {
      final decoded = jsonDecode(_prefs.getString(ConversationStore._tombKey) ?? '{}');
      if (decoded is Map) {
        return decoded.map((k, v) =>
            MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
      }
    } catch (_) {}
    return {};
  }

  Future<void> add(String id, {int? deletedAt}) async {
    final t = get();
    t[id] = deletedAt ?? DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(
        ConversationStore._tombKey, jsonEncode(t));
  }

  @override
  Future<void> remove(Iterable<String> ids) async {
    final t = get();
    var changed = false;
    for (final id in ids) {
      if (t.remove(id) != null) changed = true;
    }
    if (changed) {
      await _prefs.setString(
          ConversationStore._tombKey, jsonEncode(t));
    }
  }

  Future<void> clear() async =>
      _prefs.remove(ConversationStore._tombKey);
}

/// زمانِ آخرین همگام‌سازیِ موفق.
Future<int> getLastSyncAt(SharedPreferences prefs) async =>
    prefs.getInt(ConversationStore._lastKey) ?? 0;

Future<void> setLastSyncAt(SharedPreferences prefs, int ts) async =>
    prefs.setInt(ConversationStore._lastKey, ts);
