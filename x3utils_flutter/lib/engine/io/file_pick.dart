// Drop-in for `import 'package:file_selector/file_selector.dart'`.
// Native re-exports it unchanged; web wraps picks into the VFS.
export 'file_pick_native.dart' if (dart.library.js_interop) 'file_pick_web.dart';
