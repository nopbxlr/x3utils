// Drop-in replacement for `import 'dart:io'` in the engine's file-oriented code.
// Native (and the analyzer's default) get the real dart:io; web gets a
// VFS-backed shim. `dart.library.js_interop` is web-only.
export 'io_native.dart' if (dart.library.js_interop) 'io_web.dart';
