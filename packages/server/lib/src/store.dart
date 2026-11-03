import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

/// A saved room.
class SavedRoom {
  /// Creates a save.
  const SavedRoom(
      {required this.code, required this.json, required this.savedAt});

  /// Room code.
  final String code;

  /// Room snapshot JSON.
  final Map<String, Object?> json;

  /// Save time, ms since epoch.
  final int savedAt;
}

/// Thrown when a save cannot be read.
class CorruptSaveException implements Exception {
  /// Creates the exception.
  CorruptSaveException(this.code, this.reason);

  /// Room code.
  final String code;

  /// Why it failed.
  final String reason;

  @override
  String toString() => 'Save for room $code is corrupt: $reason';
}

/// Where rooms are saved. Voice clips are never stored.
abstract interface class GameStore {
  /// Saves (replaces) a room snapshot.
  void save(String code, Map<String, Object?> json, int savedAt);

  /// Loads a room; `null` if absent; throws [CorruptSaveException].
  SavedRoom? load(String code);

  /// All saves, newest first. Corrupt entries are skipped and reported in
  /// [errors].
  List<SavedRoom> list({List<String>? errors});

  /// Deletes a save.
  void delete(String code);
}

/// In-memory store (tests, or when saving is off).
class MemoryStore implements GameStore {
  final Map<String, SavedRoom> _rooms = {};

  @override
  void save(String code, Map<String, Object?> json, int savedAt) =>
      _rooms[code] = SavedRoom(
          code: code,
          json: (jsonDecode(jsonEncode(json)) as Map).cast(),
          savedAt: savedAt);

  @override
  SavedRoom? load(String code) => _rooms[code];

  @override
  List<SavedRoom> list({List<String>? errors}) =>
      _rooms.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  @override
  void delete(String code) => _rooms.remove(code);
}

/// One JSON file per room (local hosting on the phone).
class JsonFileStore implements GameStore {
  /// Creates a store in [dir].
  JsonFileStore(this.dir) {
    dir.createSync(recursive: true);
  }

  /// Save directory.
  final Directory dir;

  File _file(String code) => File('${dir.path}/room_$code.json');

  @override
  void save(String code, Map<String, Object?> json, int savedAt) {
    final tmp = File('${_file(code).path}.tmp');
    tmp.writeAsStringSync(jsonEncode({'savedAt': savedAt, 'room': json}));
    tmp.renameSync(_file(code).path);
  }

  @override
  SavedRoom? load(String code) {
    final f = _file(code);
    if (!f.existsSync()) return null;
    return _parse(code, f.readAsStringSync());
  }

  SavedRoom _parse(String code, String text) {
    try {
      final doc = (jsonDecode(text) as Map).cast<String, Object?>();
      return SavedRoom(
          code: code,
          json: (doc['room'] as Map).cast(),
          savedAt: doc['savedAt'] as int);
    } catch (e) {
      throw CorruptSaveException(code, '$e');
    }
  }

  @override
  List<SavedRoom> list({List<String>? errors}) {
    final out = <SavedRoom>[];
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.startsWith('room_') || !name.endsWith('.json')) continue;
      final code = name.substring(5, name.length - 5);
      try {
        out.add(_parse(code, f.readAsStringSync()));
      } on CorruptSaveException catch (e) {
        errors?.add(e.toString());
      }
    }
    return out..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  @override
  void delete(String code) {
    final f = _file(code);
    if (f.existsSync()) f.deleteSync();
  }
}

/// SQLite store for the online server (Docker volume).
class SqliteStore implements GameStore {
  /// Opens or creates the database at [path].
  SqliteStore(String path) {
    if (Platform.isWindows) {
      // Windows ships winsqlite3.dll; use it when sqlite3.dll is absent.
      open.overrideFor(OperatingSystem.windows, () {
        try {
          return DynamicLibrary.open('sqlite3.dll');
        } catch (_) {
          return DynamicLibrary.open('winsqlite3.dll');
        }
      });
    }
    _db = sqlite3.open(path);
    _db.execute('CREATE TABLE IF NOT EXISTS rooms ('
        'code TEXT PRIMARY KEY, json TEXT NOT NULL, saved_at INTEGER NOT NULL)');
  }

  late final Database _db;

  @override
  void save(String code, Map<String, Object?> json, int savedAt) => _db.execute(
      'INSERT INTO rooms (code, json, saved_at) VALUES (?, ?, ?) '
      'ON CONFLICT(code) DO UPDATE SET json = excluded.json, '
      'saved_at = excluded.saved_at',
      [code, jsonEncode(json), savedAt]);

  @override
  SavedRoom? load(String code) {
    final rows =
        _db.select('SELECT json, saved_at FROM rooms WHERE code = ?', [code]);
    if (rows.isEmpty) return null;
    return _row(
        code, rows.first['json'] as String, rows.first['saved_at'] as int);
  }

  SavedRoom _row(String code, String json, int savedAt) {
    try {
      return SavedRoom(
          code: code, json: (jsonDecode(json) as Map).cast(), savedAt: savedAt);
    } catch (e) {
      throw CorruptSaveException(code, '$e');
    }
  }

  @override
  List<SavedRoom> list({List<String>? errors}) {
    final out = <SavedRoom>[];
    for (final r in _db.select(
        'SELECT code, json, saved_at FROM rooms ORDER BY saved_at DESC')) {
      try {
        out.add(_row(
            r['code'] as String, r['json'] as String, r['saved_at'] as int));
      } on CorruptSaveException catch (e) {
        errors?.add(e.toString());
      }
    }
    return out;
  }

  @override
  void delete(String code) =>
      _db.execute('DELETE FROM rooms WHERE code = ?', [code]);

  /// Closes the database.
  void close() => _db.dispose();
}
