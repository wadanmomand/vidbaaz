/// Notifies Android's media scanner about a newly saved file.
///
/// Gallery apps read Android's MediaStore, not the filesystem directly.
/// Files written to `Download/…` without a scan are invisible to Gallery
/// until the system rescans — that was issue #26 (downloader videos
/// showed only in the app's Saved tab, never in Gallery), while status
/// saves already scanned and appeared at once. Reuses the existing
/// `com.aatishstudio.vidbaaz/media` channel handled in MainActivity.
/// Failures are swallowed: a missed scan must never break a download.
library;

import 'package:flutter/services.dart';

class MediaScan {
  static const _channel =
      MethodChannel('com.aatishstudio.vidbaaz/media');

  static Future<void> scanFile(String path) async {
    try {
      await _channel.invokeMethod('scanFile', {'path': path});
    } catch (_) {
      // Best effort only — the file itself is already saved.
    }
  }
}
