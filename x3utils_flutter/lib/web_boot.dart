// Web-aware bootstrap, selected by platform. Native gets no-ops; web loads the
// VFS and overlays the saved-files button. Lets the default main.dart entry
// work everywhere (no separate web entry point needed).
export 'web_boot_stub.dart' if (dart.library.js_interop) 'web_boot_web.dart';
