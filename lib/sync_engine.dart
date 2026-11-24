// موتور همگام‌سازیِ گفت‌وگوها — پورتِ js/sync.js (runSync).
// قواعد: هر گفت‌وگو جدا همگام می‌شود؛ «آخرین تغییر برنده است»؛ حذف‌ها با
// سنگ‌قبر منتقل می‌شوند؛ محتوا قبل از ارسال رمز می‌شود و سرور فقط متنِ
// رمزشده می‌بیند؛ عکس‌های base64 همگام نمی‌شوند.

import 'dart:typed_data';

import 'models.dart';
import 'sync_crypto.dart';

const _pullBatch = 3;

/// نتیجهٔ یک دور همگام‌سازی.
class SyncResult {
  final List<String> pulled;
  int pushed;
  final List<String> deletedLocal;
  int deletedRemote;
  int tooLarge;
  final List<String> errors;

  SyncResult({
    List<String>? pulled,
    this.pushed = 0,
    List<String>? deletedLocal,
    this.deletedRemote = 0,
    this.tooLarge = 0,
    List<String>? errors,
  })  : pulled = pulled ?? [],
        deletedLocal = deletedLocal ?? [],
        errors = errors ?? [];
}

/// نمای سبکِ گفت‌وگوهای محلی (فقط id و updated_at).
class LocalMeta {
  final String id;
  final int updatedAt;
  const LocalMeta(this.id, this.updatedAt);
}

/// وابستگی‌های ذخیره‌سازیِ محلی.
abstract class SyncLocalStore {
  Future<List<LocalMeta>> list();
  Future<Conversation?> get(String id);
  Future<void> putRaw(Conversation conv);
  Future<void> remove(String id);
}

/// سنگ‌قبرهای حذف (id → زمان حذف بر حسب میلی‌ثانیه).
abstract class SyncTombstones {
  Map<String, int> get();
  Future<void> remove(Iterable<String> ids);
}

typedef SyncApiCall = Future<Map<String, dynamic>> Function(
    String action, Map<String, dynamic> payload);

/// اجرای یک دور کامل همگام‌سازی. `shouldSkip` یعنی این گفت‌وگو الان درگیر
/// است (مثلاً در حال استریم) و دست نزن.
Future<SyncResult> runSync({
  required SyncApiCall api,
  required Uint8List aesKey,
  required SyncLocalStore local,
  required SyncTombstones tombstones,
  bool Function(String id)? shouldSkip,
}) async {
  final result = SyncResult();
  final skip = shouldSkip ?? (_) => false;

  final listData = await api('list', {});
  final remoteRaw = listData['items'];
  final remote = <String, ({int u, bool d})>{};
  if (remoteRaw is Map) {
    remoteRaw.forEach((key, value) {
      if (key is String && value is Map) {
        remote[key] = (
          u: (value['u'] as num?)?.toInt() ?? 0,
          d: value['d'] == true,
        );
      }
    });
  }
  final locals = await local.list();
  final snapshot = {for (final c in locals) c.id: c};
  final lmap = Map<String, LocalMeta>.from(snapshot);
  final tomb = Map<String, int>.from(tombstones.get());

  final pull = <String>[];
  final push = <String>[];
  final delRemote = <({String id, int u})>[];
  final delLocal = <String>{};
  final ack = <String>{};

  for (final entry in tomb.entries) {
    final id = entry.key;
    final t = entry.value;
    final l = lmap[id];
    if (l != null && l.updatedAt > t) {
      ack.add(id);
      tomb.remove(id);
    } else if (l != null) {
      delLocal.add(id);
      lmap.remove(id);
    }
  }

  for (final entry in remote.entries) {
    final id = entry.key;
    final r = entry.value;
    final l = lmap[id];
    final t = tomb[id];
    if (r.d) {
      if (l != null) {
        if (l.updatedAt <= r.u) {
          delLocal.add(id);
        } else {
          push.add(id); // بعد از حذف، اینجا ویرایش شده → زنده می‌شود
        }
      }
      if (t != null) ack.add(id);
    } else if (t != null) {
      if (t >= r.u) {
        delRemote.add((id: id, u: t));
      } else {
        pull.add(id); // روی دستگاه دیگر بعد از حذفِ من ویرایش شده
        ack.add(id);
      }
    } else if (l == null) {
      pull.add(id);
    } else if (r.u > l.updatedAt) {
      pull.add(id);
    } else if (r.u < l.updatedAt) {
      push.add(id);
    }
  }
  for (final l in lmap.values) {
    if (!remote.containsKey(l.id)) push.add(l.id);
  }
  for (final id in tomb.keys) {
    if (!remote.containsKey(id)) ack.add(id);
  }

  // اگر هم «دریافت» و هم «حذف محلی» برنامه‌ریزی شده، دریافت برنده است.
  for (final id in pull) {
    delLocal.remove(id);
  }

  // ۱) دریافت
  for (var i = 0; i < pull.length; i += _pullBatch) {
    final ids = pull.sublist(
        i, i + _pullBatch > pull.length ? pull.length : i + _pullBatch);
    Map<String, dynamic> items;
    try {
      items = (await api('get', {'ids': ids}))['items']
              as Map<String, dynamic>? ??
          {};
    } catch (e) {
      result.errors.add(e.toString());
      continue;
    }
    for (final id in ids) {
      try {
        if (skip(id)) continue;
        final cipher = items[id];
        if (cipher is! String || cipher.isEmpty) {
          throw const FormatException('گفت‌وگو روی سرور پیدا نشد.');
        }
        final decoded = decryptSyncJson(aesKey, cipher);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('ساختار گفت‌وگوی دریافتی نامعتبر است.');
        }
        final conv = sanitizeConversation(decoded, id);
        conv.updatedAt = remote[id]?.u ?? conv.updatedAt;
        final before = snapshot[id];
        final current = await local.get(id);
        if ((current != null &&
                (before == null ||
                    current.updatedAt != before.updatedAt)) ||
            (current == null && before != null)) {
          continue;
        }
        mergeOmittedImages(conv, current);
        await local.putRaw(conv);
        result.pulled.add(id);
      } catch (e) {
        result.errors.add(e.toString());
      }
    }
  }

  // ۲) ارسال
  for (final id in push) {
    try {
      final conv = await local.get(id);
      if (conv == null) continue;
      final cipher = encryptSyncJson(aesKey, conv.toSyncPayload());
      if (cipher.length > maxSyncItemChars) {
        result.tooLarge++;
        continue;
      }
      final res = await api('put', {
        'items': [
          {'id': id, 'u': conv.updatedAt, 'c': cipher},
        ],
      });
      final results = res['results'];
      final status =
          results is Map ? results[id] as String? : null;
      if (status == 'ok') {
        result.pushed++;
      } else if (status == 'limit') {
        result.errors.add('تعداد گفت‌وگوهای همگام‌شده به سقف رسیده است.');
      }
      // 'stale' یعنی روی سرور نسخهٔ جدیدتری هست؛ دفعهٔ بعد دریافت می‌شود.
    } catch (e) {
      result.errors.add(e.toString());
    }
  }

  // ۳) حذف از سرور (سنگ‌قبرهای محلی)
  if (delRemote.isNotEmpty) {
    try {
      await api('delete', {
        'items': delRemote
            .map((e) => {'id': e.id, 'u': e.u})
            .toList(),
      });
      result.deletedRemote = delRemote.length;
      for (final e in delRemote) {
        ack.add(e.id);
      }
    } catch (e) {
      result.errors.add(e.toString());
    }
  }

  // ۴) حذف محلی
  for (final id in delLocal) {
    try {
      if (skip(id)) continue;
      await local.remove(id);
      result.deletedLocal.add(id);
    } catch (e) {
      result.errors.add(e.toString());
    }
  }

  await tombstones.remove(ack);
  return result;
}
