// Native reveals paths in the OS file manager (Process); web can't, so it keeps
// the same compact path display with copy, and turns reveal into copy.
export 'desktop_path_display_io.dart' if (dart.library.js_interop) 'desktop_path_display_web.dart';
