import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'outbox.dart';

/// The store the queue uses where there is a file system: every platform but
/// the web. Imported only there, so the package itself stays usable on the web.
OutboxStore defaultOutboxStore() => FileOutboxStore();

/// One JSON file per comment, in the app's support directory.
///
/// Files, not shared_preferences. A queued comment carries its screenshot, up
/// to a few megabytes of base64, and on Android the host app's preferences are
/// one XML file read whole at every launch. Parking megabytes in it would slow
/// the host's startup for the sake of a feature the host did not write.
class FileOutboxStore implements OutboxStore {
  FileOutboxStore([this._dir]);

  Directory? _dir;

  Future<Directory> _directory() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    return _dir = Directory('${base.path}/guidester_outbox');
  }

  @override
  Future<Map<String, String>> readAll() async {
    final dir = await _directory();
    if (!dir.existsSync()) return {};
    final out = <String, String>{};
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.uri.pathSegments.last;
      try {
        out[name] = await entity.readAsString();
      } catch (_) {
        out[name] = ''; // unreadable: reported as such, and removed by load()
      }
    }
    return out;
  }

  @override
  Future<void> write(String name, String contents) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    // Written aside and renamed, so a process killed mid-write leaves no half
    // a comment behind to be sent later as garbage.
    final tmp = File('${dir.path}/$name.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename('${dir.path}/$name');
  }

  @override
  Future<void> delete(String name) async {
    final dir = await _directory();
    final file = File('${dir.path}/$name');
    if (file.existsSync()) await file.delete();
  }
}
