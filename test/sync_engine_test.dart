import 'package:aichat/models.dart';
import 'package:aichat/sync_crypto.dart';
import 'package:aichat/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLocal implements SyncLocalStore {
  final Map<String, Conversation> data = {};

  @override
  Future<List<LocalMeta>> list() async =>
      data.values.map((c) => LocalMeta(c.id, c.updatedAt)).toList();

  @override
  Future<Conversation?> get(String id) async => data[id];

  @override
  Future<void> putRaw(Conversation conv) async {
    data[conv.id] = conv;
  }

  @override
  Future<void> remove(String id) async {
    data.remove(id);
  }
}

class FakeTombs implements SyncTombstones {
  final Map<String, int> tomb = {};

  @override
  Map<String, int> get() => Map.of(tomb);

  @override
  Future<void> remove(Iterable<String> ids) async {
    for (final id in ids) {
      tomb.remove(id);
    }
  }
}

/// سرورِ جعلی: meta = id -> (u, d)، data = id -> cipher.
class FakeRemote {
  final Map<String, ({int u, bool d})> meta = {};
  final Map<String, String> data = {};

  Future<Map<String, dynamic>> call(
      String action, Map<String, dynamic> payload) async {
    switch (action) {
      case 'list':
        return {
          'items': meta.map((k, v) => MapEntry(k, {'u': v.u, 'd': v.d})),
        };
      case 'get':
        final ids = (payload['ids'] as List).cast<String>();
        return {
          'items': {for (final id in ids) id: data[id]},
        };
      case 'put':
        final items = payload['items'] as List;
        final results = <String, String>{};
        for (final it in items) {
          final m = it as Map<String, dynamic>;
          final id = m['id'] as String;
          final u = m['u'] as int;
          final cur = meta[id];
          if (cur != null && cur.u >= u) {
            results[id] = 'stale';
          } else {
            meta[id] = (u: u, d: false);
            data[id] = m['c'] as String;
            results[id] = 'ok';
          }
        }
        return {'results': results};
      case 'delete':
        final items = payload['items'] as List;
        for (final it in items) {
          final m = it as Map<String, dynamic>;
          final id = m['id'] as String;
          meta[id] = (u: m['u'] as int, d: true);
          data.remove(id);
        }
        return {'results': {}};
      default:
        throw StateError('unknown action $action');
    }
  }
}

Conversation conv(String id, int updatedAt, [String text = 'سلام']) =>
    Conversation(
      id: id,
      title: 't',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      messages: [ChatMessage(role: 'user', content: text)],
    );

void main() {
  final keys = deriveSyncKeys('ABCD-EFGH-JKLM-NPQR-STUV');

  test('pulls a conversation that exists only on the server', () async {
    final local = FakeLocal();
    final tombs = FakeTombs();
    final remote = FakeRemote();
    final cipher = encryptSyncJson(keys.aesKey, conv('c1', 100).toSyncPayload());
    remote.meta['c1'] = (u: 100, d: false);
    remote.data['c1'] = cipher;

    final r = await runSync(
      api: remote.call,
      aesKey: keys.aesKey,
      local: local,
      tombstones: tombs,
    );
    expect(r.pulled, ['c1']);
    expect(r.errors, isEmpty);
    expect(local.data['c1']?.messages.first.content, 'سلام');
  });

  test('pushes a local-only conversation', () async {
    final local = FakeLocal();
    final tombs = FakeTombs();
    final remote = FakeRemote();
    local.data['c2'] = conv('c2', 200);

    final r = await runSync(
      api: remote.call,
      aesKey: keys.aesKey,
      local: local,
      tombstones: tombs,
    );
    expect(r.pushed, 1);
    expect(remote.meta['c2']?.u, 200);
    expect(remote.data['c2'], isNotNull);
  });

  test('last-write-wins on conflict', () async {
    final local = FakeLocal();
    final tombs = FakeTombs();
    final remote = FakeRemote();
    local.data['c3'] = conv('c3', 300, 'local-new');
    remote.meta['c3'] = (u: 400, d: false);
    remote.data['c3'] = encryptSyncJson(
        keys.aesKey, conv('c3', 400, 'remote-new').toSyncPayload());

    final r = await runSync(
      api: remote.call,
      aesKey: keys.aesKey,
      local: local,
      tombstones: tombs,
    );
    expect(r.pulled, ['c3']);
    expect(local.data['c3']?.messages.first.content, 'remote-new');
  });

  test('local delete propagates to server as tombstone', () async {
    final local = FakeLocal();
    final tombs = FakeTombs();
    final remote = FakeRemote();
    remote.meta['c4'] = (u: 100, d: false);
    remote.data['c4'] = encryptSyncJson(
        keys.aesKey, conv('c4', 100).toSyncPayload());
    tombs.tomb['c4'] = 500;

    final r = await runSync(
      api: remote.call,
      aesKey: keys.aesKey,
      local: local,
      tombstones: tombs,
    );
    expect(r.deletedRemote, 1);
    expect(remote.meta['c4']?.d, isTrue);
    expect(tombs.tomb, isEmpty); // ack شد
  });

  test('remote delete removes local conversation', () async {
    final local = FakeLocal();
    final tombs = FakeTombs();
    final remote = FakeRemote();
    local.data['c5'] = conv('c5', 100);
    remote.meta['c5'] = (u: 200, d: true);

    final r = await runSync(
      api: remote.call,
      aesKey: keys.aesKey,
      local: local,
      tombstones: tombs,
    );
    expect(r.deletedLocal, ['c5']);
    expect(local.data.containsKey('c5'), isFalse);
  });

  test('edited-after-delete resurrects locally', () async {
    final local = FakeLocal();
    final tombs = FakeTombs();
    final remote = FakeRemote();
    local.data['c6'] = conv('c6', 300);
    remote.meta['c6'] = (u: 200, d: true);

    final r = await runSync(
      api: remote.call,
      aesKey: keys.aesKey,
      local: local,
      tombstones: tombs,
    );
    expect(r.pushed, 1);
    expect(remote.meta['c6']?.d, isFalse);
  });

  test('skips conversation that is streaming', () async {
    final local = FakeLocal();
    final tombs = FakeTombs();
    final remote = FakeRemote();
    remote.meta['c7'] = (u: 100, d: false);
    remote.data['c7'] = encryptSyncJson(
        keys.aesKey, conv('c7', 100).toSyncPayload());

    final r = await runSync(
      api: remote.call,
      aesKey: keys.aesKey,
      local: local,
      tombstones: tombs,
      shouldSkip: (id) => id == 'c7',
    );
    expect(r.pulled, isEmpty);
    expect(local.data.containsKey('c7'), isFalse);
  });
}
