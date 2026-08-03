// Web-only "saved files" browser. Backups (and packaged firmware) are persisted
// to IndexedDB by the VFS, so they survive even if the automatic download is
// missed or cancelled. This lets the user browse those persisted files and
// re-download any of them — reliably, via the File System Access API, which can
// tell whether the save actually completed or was aborted.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'engine/io/vfs.dart';
import 'theme.dart';

// File System Access API (Chrome/Edge). Bound directly — package:web has it,
// but binding here keeps availability-checking simple.
@JS('window.showSaveFilePicker')
external JSAny? get _fsaFn;

@JS('window.showSaveFilePicker')
external JSPromise<_FsHandle> _showSaveFilePicker(JSObject options);

extension type _FsHandle._(JSObject _) implements JSObject {
  external JSPromise<_FsWritable> createWritable();
}

extension type _FsWritable._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSAny data);
  external JSPromise<JSAny?> close();
}

enum SaveResult { saved, cancelled, downloaded }

/// Save [bytes] to disk. Prefers the File System Access API so a cancelled save
/// is detectable (returns [SaveResult.cancelled]); the file is never lost —
/// it stays in the VFS/IndexedDB. Falls back to an anchor download where the
/// API is unavailable (completion can't be detected there).
Future<SaveResult> saveBytes(String name, Uint8List bytes) async {
  if (_fsaFn != null) {
    try {
      final opts = <String, dynamic>{'suggestedName': name}.jsify()! as JSObject;
      final handle = await _showSaveFilePicker(opts).toDart;
      final writable = await handle.createWritable().toDart;
      await writable.write(bytes.toJS).toDart;
      await writable.close().toDart; // completing close() == the bytes landed
      return SaveResult.saved;
    } catch (_) {
      // Almost always the user cancelled the picker (AbortError). The file is
      // still safe in the browser, so this is "cancelled", not "lost".
      return SaveResult.cancelled;
    }
  }
  _anchorDownload(name, bytes);
  return SaveResult.downloaded;
}

void _anchorDownload(String name, Uint8List bytes) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/octet-stream'));
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = name;
  web.document.body?.appendChild(a);
  a.click();
  a.remove();
  Future<void>.delayed(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
}

/// Small floating button that opens the saved-files browser. Overlaid on the
/// real app on web only, so the base UI is untouched.
class SavedFilesButton extends StatelessWidget {
  const SavedFilesButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 56,
      child: Material(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(24),
        elevation: 6,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const _SavedFilesDialog(),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_rounded, color: Colors.black, size: 20),
                SizedBox(width: 8),
                Text('Saved files',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedFilesDialog extends StatefulWidget {
  const _SavedFilesDialog();
  @override
  State<_SavedFilesDialog> createState() => _SavedFilesDialogState();
}

class _SavedFilesDialogState extends State<_SavedFilesDialog> {
  String? _busyPath;
  String? _note;

  @override
  Widget build(BuildContext context) {
    final files = Vfs.instance.savedFiles();
    return Dialog(
      backgroundColor: AppColors.panel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_rounded, color: AppColors.brand, size: 20),
                  const SizedBox(width: 8),
                  Text('Saved files',
                      style: TextStyle(color: AppColors.txt, fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: AppColors.dim),
                  ),
                ],
              ),
              Text(
                'Backups persist in this browser even if a download is cancelled. '
                'Re-download any of them here.',
                style: TextStyle(color: AppColors.mut, fontSize: 12),
              ),
              if (_note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_note!, style: TextStyle(color: AppColors.hold, fontSize: 12)),
                ),
              const SizedBox(height: 10),
              Flexible(
                child: files.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Text('No saved files yet. Run a backup first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.mut)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: files.length,
                        separatorBuilder: (_, _) => Divider(color: AppColors.line, height: 1),
                        itemBuilder: (context, i) => _row(files[i].path, files[i].size),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String path, int size) {
    final name = Vfs.basename(path);
    final kb = (size / 1024).toStringAsFixed(size >= 1024 ? 0 : 1);
    final busy = _busyPath == path;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.txt, fontFamily: kMono, fontSize: 13)),
                Text('$size bytes · $kb KB',
                    style: TextStyle(color: AppColors.mut, fontSize: 11)),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            IconButton(
              tooltip: 'Download',
              onPressed: () => _download(path),
              icon: Icon(Icons.download_rounded, color: AppColors.brand),
            ),
            IconButton(
              tooltip: 'Delete from browser',
              onPressed: () => _delete(path),
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _download(String path) async {
    setState(() {
      _busyPath = path;
      _note = null;
    });
    try {
      final bytes = Vfs.instance.read(path);
      final result = await saveBytes(Vfs.basename(path), bytes);
      _note = switch (result) {
        SaveResult.saved => 'Saved ${Vfs.basename(path)}.',
        SaveResult.cancelled => 'Save cancelled — the file is kept here, try again anytime.',
        SaveResult.downloaded => 'Download started for ${Vfs.basename(path)}.',
      };
    } catch (e) {
      _note = 'Could not read the file: $e';
    } finally {
      if (mounted) setState(() => _busyPath = null);
    }
  }

  Future<void> _delete(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Delete saved file?'),
        content: Text('Remove ${Vfs.basename(path)} from the browser? This cannot be undone.',
            style: TextStyle(color: AppColors.dim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      Vfs.instance.deleteFile(path);
      if (mounted) setState(() => _note = 'Deleted ${Vfs.basename(path)}.');
    }
  }
}
