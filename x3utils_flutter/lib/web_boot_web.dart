// Web: load the persistent VFS before the app starts, and overlay the
// saved-files button on the real HomeScreen.
import 'package:flutter/widgets.dart';

import 'engine/io/vfs.dart';
import 'web_files.dart';

Future<void> initWebStorage() => Vfs.instance.load();

Widget wrapHome(Widget home) => Stack(
  children: [
    Positioned.fill(child: home),
    const SavedFilesButton(),
  ],
);
