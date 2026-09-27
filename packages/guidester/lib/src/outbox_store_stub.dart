import 'outbox.dart';

/// The web has no file system for the queue. [Outbox] never writes on the web
/// (a send that fails there shows its error, as before); this exists so the
/// package compiles for it.
OutboxStore defaultOutboxStore() => _NoStore();

class _NoStore implements OutboxStore {
  @override
  Future<Map<String, String>> readAll() async => const {};

  @override
  Future<void> write(String name, String contents) async =>
      throw UnsupportedError('No offline queue on this platform');

  @override
  Future<void> delete(String name) async {}
}
