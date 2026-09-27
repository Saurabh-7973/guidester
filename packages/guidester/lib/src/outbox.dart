import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'outbox_store_stub.dart' if (dart.library.io) 'outbox_store_io.dart';

/// Where queued comments are kept. A seam for tests: the app writes files, a
/// widget test cannot, because real file I/O never completes under fake time.
abstract class OutboxStore {
  /// Every stored entry, by name. Names sort oldest first.
  Future<Map<String, String>> readAll();
  Future<void> write(String name, String contents);
  Future<void> delete(String name);
}

/// A test's store. Lives only as long as the object.
class MemoryOutboxStore implements OutboxStore {
  final Map<String, String> entries = {};

  @override
  Future<Map<String, String>> readAll() async => Map.of(entries);

  @override
  Future<void> write(String name, String contents) async =>
      entries[name] = contents;

  @override
  Future<void> delete(String name) async => entries.remove(name);
}

/// A comment that could not be sent yet.
class QueuedComment {
  const QueuedComment({
    required this.name,
    required this.payload,
    required this.queuedAt,
  });

  final String name;

  /// The request body minus the api key, which is added at send time. A key
  /// rotated between the queue and the retry means a newer build, and the
  /// newer build's key is the one that will be accepted.
  final Map<String, dynamic> payload;
  final DateTime queuedAt;
}

/// Comments sent while the phone could not reach the server.
///
/// A tester in a lift, a basement or a train pressed Send and got an error;
/// the deep review's point was that one lost report is enough for them to
/// stop trusting the button. A send that fails for a reason a retry can fix
/// is kept here instead, the composer closes as if it went, and the comment
/// goes when the network comes back.
///
/// Each comment carries a `client_id` made once, before its first attempt. A
/// timeout can hide a request that did arrive, so the retry sends the same id
/// and the server (migration 0011) answers "already have it" rather than
/// storing it twice.
class Outbox {
  Outbox._();

  /// More than this and the oldest go. Twenty unsent comments is a phone that
  /// has been offline for days, and the screenshots are the expensive part.
  static const int maxItems = 20;

  /// A comment this old describes a build nobody is testing any more.
  static const Duration maxAge = Duration(days: 14);

  static OutboxStore? _store;
  static OutboxStore get _active => _store ??= defaultOutboxStore();

  /// Tests replace the store; [debugReset] puts the file store back.
  static set debugStore(OutboxStore store) => _store = store;

  static final Random _random = Random.secure();

  /// A fresh idempotency key: 32 hex characters.
  static String newClientId() => [
        for (var i = 0; i < 16; i++)
          _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();

  /// Keeps [payload]. False when it could not be kept, and then the caller
  /// must show the failure instead of pretending the comment is safe.
  static Future<bool> add(Map<String, dynamic> payload) async {
    if (kIsWeb) return false;
    try {
      final now = DateTime.now();
      final id = payload['client_id'] ?? newClientId();
      // Zero-padded time first, so names sort in the order they were queued.
      final name =
          '${now.millisecondsSinceEpoch.toString().padLeft(15, '0')}-$id.json';
      final stored = Map<String, dynamic>.of(payload)..remove('api_key');
      await _active.write(
        name,
        jsonEncode({
          'queued_at': now.toUtc().toIso8601String(),
          'payload': stored,
        }),
      );
      await _trim();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Everything queued, oldest first. Drops what cannot be read or is past
  /// [maxAge] as it goes. Never throws.
  static Future<List<QueuedComment>> load() async {
    if (kIsWeb) return const [];
    try {
      final raw = await _active.readAll();
      final names = raw.keys.toList()..sort();
      final out = <QueuedComment>[];
      final now = DateTime.now();
      for (final name in names) {
        final item = _parse(name, raw[name]!);
        if (item == null || now.difference(item.queuedAt) > maxAge) {
          await _forget(name);
          continue;
        }
        out.add(item);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<int> get length async => (await load()).length;

  static Future<void> remove(String name) => _forget(name);

  static QueuedComment? _parse(String name, String contents) {
    try {
      final decoded = jsonDecode(contents);
      if (decoded is! Map) return null;
      final payload = decoded['payload'];
      final at = DateTime.tryParse('${decoded['queued_at']}');
      if (payload is! Map || at == null) return null;
      return QueuedComment(
        name: name,
        payload: Map<String, dynamic>.from(payload),
        queuedAt: at,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _trim() async {
    final names = (await _active.readAll()).keys.toList()..sort();
    for (var i = 0; i < names.length - maxItems; i++) {
      await _forget(names[i]);
    }
  }

  static Future<void> _forget(String name) async {
    try {
      await _active.delete(name);
    } catch (_) {
      // Tried again on the next load.
    }
  }

  static void debugReset() => _store = null;
}

/// Sends what the [Outbox] holds, one at a time, and waits longer between
/// attempts each time the network is still not there.
///
/// Kicked on launch, when the app comes back to the foreground, and after any
/// comment goes through (proof the network is back). No connectivity plugin:
/// one more native dependency in every host app, to learn what the next
/// attempt learns anyway.
class OutboxSender {
  OutboxSender(this._api, {this.onSent});

  final ApiClient _api;

  /// How many queued comments one pass delivered, when it is more than none.
  final void Function(int sent)? onSent;

  static const List<Duration> _backoff = [
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  Timer? _timer;
  int _failures = 0;
  Future<void>? _running;
  bool _disposed = false;

  /// Starts a pass now, unless one is already going.
  Future<void> kick() {
    _timer?.cancel();
    _timer = null;
    return _running ??= _pass().whenComplete(() => _running = null);
  }

  /// Schedules a pass after the backoff, unless one is running or waiting:
  /// for a comment just queued because a send failed a moment ago.
  void later() {
    if (_disposed || _timer != null || _running != null) return;
    _schedule();
  }

  void _schedule() {
    final wait = _backoff[min(_failures, _backoff.length - 1)];
    _failures++;
    _timer = Timer(wait, () {
      _timer = null;
      kick();
    });
  }

  Future<void> _pass() async {
    var sent = 0;
    var retry = false;
    for (final item in await Outbox.load()) {
      if (_disposed) return;
      final result = await _api.sendPayload(item.payload);
      if (result.success) {
        await Outbox.remove(item.name);
        sent++;
        continue;
      }
      if (result.retryable) {
        retry = true;
        break;
      }
      if (result.status == 401) {
        // The key this build carries is refused, so is every later comment,
        // and so is the tester's next live one. Kept: a newer build with a
        // working key sends them.
        break;
      }
      // The server read it and will never accept it. Retrying forever
      // changes nothing, and the developer is told what was lost.
      debugPrint(
        '[guidester] a queued comment was refused (${result.error}) and '
        'has been dropped.',
      );
      await Outbox.remove(item.name);
    }
    if (_disposed) return;
    if (sent > 0) {
      _failures = 0;
      onSent?.call(sent);
    }
    if (retry) _schedule();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
