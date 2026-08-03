// The Windows ACP round-trip check uses dart:ffi (kernel32), which only exists
// on Windows. Web gets a stub whose methods are never reached (their callers
// are guarded by Platform.isWindows, false on web).
export 'windows_ansi_path_io.dart' if (dart.library.js_interop) 'windows_ansi_path_web.dart';
