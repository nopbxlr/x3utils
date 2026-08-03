// Web: wrap file_selector so a picked file's bytes are slurped into the VFS
// under a synthetic path that ends in the real filename. The app reads picked
// files by PATH synchronously (File(path).readAsBytesSync, extension checks),
// which a blob URL can't satisfy — this makes those paths real VFS entries.
import 'package:file_selector/file_selector.dart' as fs;

import 'vfs.dart';

export 'package:file_selector/file_selector.dart' show XFile, XTypeGroup;

Future<fs.XFile?> openFile({
  List<fs.XTypeGroup> acceptedTypeGroups = const <fs.XTypeGroup>[],
  String? initialDirectory,
  String? confirmButtonText,
}) async {
  final picked = await fs.openFile(
    acceptedTypeGroups: acceptedTypeGroups,
    initialDirectory: initialDirectory,
    confirmButtonText: confirmButtonText,
  );
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  final name = picked.name.isEmpty ? 'firmware.bin' : picked.name;
  final vpath = Vfs.norm('/picked/${DateTime.now().microsecondsSinceEpoch}_$name');
  // Input file: keep it in memory for sync reads, but don't download or persist.
  Vfs.instance.write(vpath, bytes, allowDownload: false, persist: false);
  return fs.XFile(vpath, name: name, bytes: bytes, length: bytes.length);
}

/// No writable directory concept in the browser; the root stays the VFS default.
Future<String?> getDirectoryPath({
  String? initialDirectory,
  String? confirmButtonText,
}) async => null;
