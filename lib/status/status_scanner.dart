/// Pure-Dart status-folder scanner: discovers WhatsApp-family `.Statuses`
/// folders on external storage and lists their media, newest first.
///
/// Kept dependency-free so it is fully unit-testable against any root dir.
library;

import 'dart:io';

import 'status_models.dart';

class StatusScanner {
  static const imageExts = {'.jpg', '.jpeg', '.png', '.gif', '.webp'};
  static const videoExts = {'.mp4', '.3gp', '.mkv', '.mov'};

  /// Candidate `.Statuses` folders, in priority order.
  ///
  /// Android 11+ scoped storage moved WhatsApp media under
  /// `Android/media/<pkg>/...`; older installs keep the legacy
  /// top-level `WhatsApp/` tree. Both are checked.
  static List<({StatusApp app, String subPath})> candidates(String storageRoot) => [
        (
          app: StatusApp.whatsapp,
          subPath:
              '$storageRoot/Android/media/com.whatsapp/WhatsApp/Media/.Statuses'
        ),
        (
          app: StatusApp.whatsapp,
          subPath: '$storageRoot/WhatsApp/Media/.Statuses'
        ),
        (
          app: StatusApp.whatsappBusiness,
          subPath:
              '$storageRoot/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses'
        ),
        (
          app: StatusApp.whatsappBusiness,
          subPath: '$storageRoot/WhatsApp Business/Media/.Statuses'
        ),
        (
          app: StatusApp.gbWhatsapp,
          subPath:
              '$storageRoot/Android/media/com.gbwhatsapp/GBWhatsApp/Media/.Statuses'
        ),
        (
          app: StatusApp.gbWhatsapp,
          subPath: '$storageRoot/GBWhatsApp/Media/.Statuses'
        ),
      ];

  /// Lists all status media under [storageRoot], newest first.
  List<StatusItem> scan(String storageRoot) {
    final items = <StatusItem>[];
    for (final c in candidates(storageRoot)) {
      final dir = Directory(c.subPath);
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync(followLinks: false)) {
        if (e is! File) continue;
        final name = e.path.split(RegExp(r'[/\\]')).last.toLowerCase();
        if (name == '.nomedia') continue;
        final dot = name.lastIndexOf('.');
        if (dot < 0) continue;
        final ext = name.substring(dot);
        final isVideo = videoExts.contains(ext);
        if (!isVideo && !imageExts.contains(ext)) continue;
        final stat = e.statSync();
        if (stat.size <= 0) continue;
        items.add(StatusItem(
          path: e.path,
          app: c.app,
          isVideo: isVideo,
          sizeBytes: stat.size,
          modified: stat.modified,
        ));
      }
    }
    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items;
  }

  /// Returns the `.Statuses` folders that actually exist (for UI labels).
  List<StatusApp> availableApps(String storageRoot) {
    final found = <StatusApp>{};
    for (final c in candidates(storageRoot)) {
      if (Directory(c.subPath).existsSync()) found.add(c.app);
    }
    return StatusApp.values.where(found.contains).toList();
  }

  /// Copies [item] into the public gallery folder and returns the new path.
  ///
  /// The caller triggers a media scan afterwards so gallery apps pick it up.
  String saveToGallery(StatusItem item, String galleryDir) {
    final dir = Directory(galleryDir)..createSync(recursive: true);
    var target = '${dir.path}/${item.fileName}';
    if (File(target).existsSync()) {
      final dot = item.fileName.lastIndexOf('.');
      final stem = item.fileName.substring(0, dot);
      final ext = item.fileName.substring(dot);
      final ts = DateTime.now().millisecondsSinceEpoch;
      target = '${dir.path}/${stem}_$ts$ext';
    }
    File(item.path).copySync(target);
    return target;
  }
}
