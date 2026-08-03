// Web stub for the Windows ANSI code-page round-trip check. Never executed on
// web (callers are guarded by Platform.isWindows); present only so shared code
// referencing these symbols compiles.
class WindowsAnsiPathResult {
  const WindowsAnsiPathResult({
    required this.originalPath,
    required this.codePage,
    required this.exact,
    this.roundTrippedPath,
    this.usedDefaultCharacter = false,
    this.conversionFailed = false,
  });

  final String originalPath;
  final int codePage;
  final bool exact;
  final String? roundTrippedPath;
  final bool usedDefaultCharacter;
  final bool conversionFailed;

  int? get firstDifferenceIndex => null;
  int? get offendingCodePoint => null;
  String? get offendingCharacter => null;
}

class WindowsAnsiPath {
  static int get activeCodePage =>
      throw UnsupportedError('Windows ACP exists only on Windows.');

  static WindowsAnsiPathResult check(String path, {int? codePage}) =>
      throw UnsupportedError('Windows ACP validation exists only on Windows.');
}
