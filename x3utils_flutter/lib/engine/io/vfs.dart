// A browser-backed virtual filesystem for the web build.
//
// The desktop app uses synchronous dart:io file APIs everywhere. IndexedDB is
// async-only, so we keep a synchronous in-memory mirror and flush every change
// to IndexedDB (via package:web) so nothing is lost across reloads. Call
// `Vfs.instance.load()` once before runApp().
//
// Writes to user artifacts (.bin / .zip) also trigger a browser download, so a
// backup lands in the user's Downloads as well as the persistent store.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const _dbName = 'x3utils_vfs';
const _store = 'files';

class Vfs {
  Vfs._();
  static final Vfs instance = Vfs._();

  final Map<String, Uint8List> _files = <String, Uint8List>{};
  final Set<String> _dirs = <String>{'/'};
  bool _loaded = false;
  web.IDBDatabase? _db;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final db = await _openDb();
      _db = db;
      final entries = await _loadAll(db);
      for (final e in entries) {
        final path = norm(e.$1);
        _files[path] = e.$2;
        _ensureParents(path);
      }
    } catch (_) {
      // First run / storage unavailable: start empty (in-memory still works).
    }
  }

  static String norm(String path) {
    var s = path.replaceAll('\\', '/').replaceAll(RegExp('/+'), '/');
    if (s.length > 1 && s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s.isEmpty ? '/' : s;
  }

  static String parentOf(String path) {
    final n = norm(path);
    final i = n.lastIndexOf('/');
    return i <= 0 ? '/' : n.substring(0, i);
  }

  static String basename(String path) {
    final n = norm(path);
    final i = n.lastIndexOf('/');
    return i < 0 ? n : n.substring(i + 1);
  }

  void _ensureParents(String path) {
    var d = parentOf(path);
    while (d != '/' && !_dirs.contains(d)) {
      _dirs.add(d);
      d = parentOf(d);
    }
  }

  // ── files ────────────────────────────────────────────────────────────
  bool fileExists(String path) => _files.containsKey(norm(path));

  Uint8List read(String path) {
    final b = _files[norm(path)];
    if (b == null) throw VfsMissing(norm(path));
    return b;
  }

  int length(String path) => read(path).length;

  void write(String path, List<int> bytes, {bool allowDownload = true, bool persist = true}) {
    final n = norm(path);
    final data = Uint8List.fromList(bytes);
    _files[n] = data;
    _ensureParents(n);
    if (persist) _persist(n, data); // async, fire-and-forget
    if (allowDownload && _isArtifact(n)) _download(n, data);
  }

  void deleteFile(String path) {
    final n = norm(path);
    _files.remove(n);
    _unpersist(n);
  }

  void rename(String from, String to) {
    final b = read(from);
    write(to, b);
    deleteFile(from);
  }

  void copy(String from, String to) => write(to, read(from));

  // ── directories ──────────────────────────────────────────────────────
  bool dirExists(String path) {
    final n = norm(path);
    if (n == '/' || _dirs.contains(n)) return true;
    final prefix = '$n/';
    return _files.keys.any((k) => k.startsWith(prefix)) || _dirs.any((d) => d.startsWith(prefix));
  }

  void createDir(String path, {bool recursive = false}) {
    final n = norm(path);
    _dirs.add(n);
    if (recursive) _ensureParents('$n/_');
  }

  void deleteDir(String path, {bool recursive = false}) {
    final n = norm(path);
    final prefix = '$n/';
    _files.keys.where((k) => k == n || k.startsWith(prefix)).toList().forEach(deleteFile);
    _dirs.removeWhere((d) => d == n || d.startsWith(prefix));
  }

  List<String> listDir(String path) {
    final n = norm(path);
    final prefix = n == '/' ? '/' : '$n/';
    final children = <String>{};
    void consider(String key) {
      if (!key.startsWith(prefix) || key == n) return;
      final rest = key.substring(prefix.length);
      final slash = rest.indexOf('/');
      children.add(prefix + (slash < 0 ? rest : rest.substring(0, slash)));
    }

    _files.keys.forEach(consider);
    _dirs.forEach(consider);
    return children.toList()..sort();
  }

  bool isDirPath(String path) => dirExists(path) && !fileExists(path);

  /// All persisted user artifacts (.bin / .zip), newest first — for the web
  /// "saved files" browser. Excludes transient staging (.part) and pick inputs.
  List<({String path, int size})> savedFiles() {
    final out = _files.entries
        .where((e) => e.value.isNotEmpty)
        .where((e) {
          final low = e.key.toLowerCase();
          if (low.endsWith('.part') || e.key.startsWith('/picked/')) return false;
          return low.endsWith('.bin') || low.endsWith('.zip');
        })
        .map((e) => (path: e.key, size: e.value.length))
        .toList();
    out.sort((a, b) => b.path.compareTo(a.path)); // timestamped names → newest first
    return out;
  }

  // ── downloads ─────────────────────────────────────────────────────────
  bool _isArtifact(String n) {
    final low = n.toLowerCase();
    if (low.contains('x3utils_backup')) return false; // hidden redundant copy
    return low.endsWith('.bin') || low.endsWith('.zip');
  }

  void _download(String n, Uint8List bytes) {
    try {
      final blob = web.Blob(
        [bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'application/octet-stream'),
      );
      final url = web.URL.createObjectURL(blob);
      final a = web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url
        ..download = basename(n);
      web.document.body?.appendChild(a);
      a.click();
      a.remove();
      Future<void>.delayed(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
    } catch (_) {}
  }

  // ── IndexedDB persistence (package:web) ─────────────────────────────────
  Future<web.IDBDatabase> _openDb() {
    final c = Completer<web.IDBDatabase>();
    final req = web.window.indexedDB.open(_dbName, 1);
    req.onupgradeneeded = (web.Event _) {
      final db = req.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_store)) db.createObjectStore(_store);
    }.toJS;
    req.onsuccess = (web.Event _) {
      c.complete(req.result as web.IDBDatabase);
    }.toJS;
    req.onerror = (web.Event _) {
      c.completeError('indexedDB open failed');
    }.toJS;
    return c.future;
  }

  Future<List<(String, Uint8List)>> _loadAll(web.IDBDatabase db) {
    final c = Completer<List<(String, Uint8List)>>();
    final out = <(String, Uint8List)>[];
    final req = db.transaction(_store.toJS, 'readonly').objectStore(_store).openCursor();
    req.onsuccess = (web.Event _) {
      final cursor = req.result as web.IDBCursorWithValue?;
      if (cursor != null) {
        final key = (cursor.key as JSString).toDart;
        final buf = (cursor.value as JSArrayBuffer).toDart;
        out.add((key, buf.asUint8List()));
        cursor.continue_();
      } else {
        c.complete(out);
      }
    }.toJS;
    req.onerror = (web.Event _) {
      c.completeError('indexedDB read failed');
    }.toJS;
    return c.future;
  }

  void _persist(String path, Uint8List data) {
    final db = _db;
    if (db == null) return;
    try {
      db.transaction(_store.toJS, 'readwrite').objectStore(_store).put(data.buffer.toJS, path.toJS);
    } catch (_) {}
  }

  void _unpersist(String path) {
    final db = _db;
    if (db == null) return;
    try {
      db.transaction(_store.toJS, 'readwrite').objectStore(_store).delete(path.toJS);
    } catch (_) {}
  }
}

class VfsMissing implements Exception {
  VfsMissing(this.path);
  final String path;
  @override
  String toString() => 'No such file: $path';
}
