import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../engine/io/io.dart' show Directory;
import '../theme.dart';

enum DesktopPathAction { none, copy, reveal }

/// Web build of the path display. There is no real filesystem in the browser —
/// files live in the browser (IndexedDB) and are downloaded — so this shows
/// "Browser storage" for directories and just the filename for files, rather
/// than a fictional path. Same constructor as the desktop widget.
class DesktopPathDisplay extends StatelessWidget {
  const DesktopPathDisplay({
    super.key,
    required this.path,
    this.action = DesktopPathAction.copy,
  });

  final String path;
  final DesktopPathAction action;

  bool get _isDirectory => Directory(path).existsSync();

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: AppColors.txt)),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
          width: 200,
          backgroundColor: AppColors.elev,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final isDir = _isDirectory;
    final title = isDir ? 'Browser storage' : p.basename(path);
    final subtitle = isDir ? 'Saved in your browser · Downloads' : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line2),
      ),
      child: Row(
        children: [
          Icon(isDir ? Icons.cloud_done_rounded : Icons.insert_drive_file_rounded,
              size: 16, color: AppColors.dim),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(
                    fontFamily: kMono,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.txt,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.dim)),
                ],
              ],
            ),
          ),
          if (action != DesktopPathAction.none && !isDir) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Copy name',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              color: AppColors.dim,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: title));
                if (context.mounted) _notify(context, 'Copied');
              },
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ],
      ),
    );
  }
}
