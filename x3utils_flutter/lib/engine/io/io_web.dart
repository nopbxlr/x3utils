// Web replacement for the subset of dart:io the app uses. Backed by the
// browser VFS (vfs.dart). Only the surface actually referenced by the engine
// is implemented; process/ffi bits are stubs (their call sites are dead on web,
// guarded by Platform.isWindows/isMacOS which are false here).
import 'dart:convert';
import 'dart:typed_data';

import 'vfs.dart';

class FileSystemException implements Exception {
  const FileSystemException([this.message = '', this.path, this.osError]);
  final String message;
  final String? path;
  final Object? osError;
  @override
  String toString() =>
      'FileSystemException: $message${path != null ? ', path = $path' : ''}';
}

class IOException implements Exception {}

class FileMode {
  const FileMode._(this.index);
  final int index; // distinguishes the const instances
  static const read = FileMode._(0);
  static const write = FileMode._(1);
  static const append = FileMode._(2);
  static const writeOnly = FileMode._(3);
  static const writeOnlyAppend = FileMode._(4);
}

abstract class FileSystemEntity {
  String get path;
  bool existsSync();
  Directory get parent => Directory(Vfs.parentOf(path));
  String get absolute => path;
}

class File implements FileSystemEntity {
  File(this.path);
  @override
  final String path;

  @override
  bool existsSync() => Vfs.instance.fileExists(path);
  Future<bool> exists() async => existsSync();

  Uint8List readAsBytesSync() => Vfs.instance.read(path);
  Future<Uint8List> readAsBytes() async => readAsBytesSync();

  String readAsStringSync({Encoding encoding = utf8}) =>
      encoding.decode(readAsBytesSync());
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      readAsStringSync(encoding: encoding);

  List<String> readAsLinesSync() => const LineSplitter().convert(readAsStringSync());

  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    if (mode == FileMode.append && Vfs.instance.fileExists(path)) {
      final b = BytesBuilder()
        ..add(Vfs.instance.read(path))
        ..add(bytes);
      Vfs.instance.write(path, b.toBytes());
    } else {
      Vfs.instance.write(path, bytes);
    }
  }

  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    writeAsBytesSync(bytes, mode: mode);
    return this;
  }

  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => writeAsBytesSync(encoding.encode(contents), mode: mode);

  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    writeAsStringSync(contents, mode: mode, encoding: encoding);
    return this;
  }

  int lengthSync() => Vfs.instance.length(path);
  Future<int> length() async => lengthSync();

  File renameSync(String newPath) {
    if (!Vfs.instance.fileExists(path)) {
      throw FileSystemException('Cannot rename, file not found', path);
    }
    Vfs.instance.rename(path, newPath);
    return File(newPath);
  }

  Future<File> rename(String newPath) async => renameSync(newPath);

  File copySync(String newPath) {
    Vfs.instance.copy(path, newPath);
    return File(newPath);
  }

  Future<File> copy(String newPath) async => copySync(newPath);

  void deleteSync({bool recursive = false}) => Vfs.instance.deleteFile(path);
  Future<File> delete({bool recursive = false}) async {
    deleteSync(recursive: recursive);
    return this;
  }

  void createSync({bool recursive = false, bool exclusive = false}) {
    if (exclusive && Vfs.instance.fileExists(path)) {
      throw FileSystemException('File already exists', path);
    }
    if (!Vfs.instance.fileExists(path)) Vfs.instance.write(path, const <int>[]);
  }

  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    createSync(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Directory get parent => Directory(Vfs.parentOf(path));
  @override
  String get absolute => path;
}

class Directory implements FileSystemEntity {
  Directory(this.path);
  @override
  final String path;

  @override
  bool existsSync() => Vfs.instance.dirExists(path);
  Future<bool> exists() async => existsSync();

  void createSync({bool recursive = false}) =>
      Vfs.instance.createDir(path, recursive: recursive);
  Future<Directory> create({bool recursive = false}) async {
    createSync(recursive: recursive);
    return this;
  }

  void deleteSync({bool recursive = false}) =>
      Vfs.instance.deleteDir(path, recursive: recursive);
  Future<Directory> delete({bool recursive = false}) async {
    deleteSync(recursive: recursive);
    return this;
  }

  List<FileSystemEntity> listSync({bool recursive = false, bool followLinks = true}) =>
      Vfs.instance
          .listDir(path)
          .map<FileSystemEntity>(
            (c) => Vfs.instance.isDirPath(c) ? Directory(c) : File(c),
          )
          .toList();

  Stream<FileSystemEntity> list({bool recursive = false, bool followLinks = true}) =>
      Stream<FileSystemEntity>.fromIterable(listSync(recursive: recursive));

  Directory createTempSync([String prefix = '']) {
    final p = '/tmp/$prefix${DateTime.now().microsecondsSinceEpoch}';
    Vfs.instance.createDir(p, recursive: true);
    return Directory(p);
  }

  Future<Directory> createTemp([String prefix = '']) async => createTempSync(prefix);

  @override
  Directory get parent => Directory(Vfs.parentOf(path));
  @override
  String get absolute => path;

  static Directory get current => Directory('/home/web');
  static Directory get systemTemp => Directory('/tmp');
}

class Platform {
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isFuchsia => false;
  static String get operatingSystem => 'web';
  static String get operatingSystemVersion => 'web';
  static String get resolvedExecutable => '/web/x3utils';
  static String get pathSeparator => '/';
  static int get numberOfProcessors => 1;
  static Map<String, String> get environment => const <String, String>{
    'HOME': '/home/web',
  };
}

// ── process stubs (dead code paths on web: only reached via Platform.isWindows)
class ProcessResult {
  ProcessResult(this.pid, this.exitCode, this.stdout, this.stderr);
  final int pid;
  final int exitCode;
  final dynamic stdout;
  final dynamic stderr;
}

class Process {
  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async => throw UnsupportedError('Process.run is not available on the web');

  static Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async => throw UnsupportedError('Process.start is not available on the web');
}
