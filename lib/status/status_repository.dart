/// Repository wiring the pure [StatusScanner] to Android storage access.
///
/// Permission strategy (matches what top status-saver apps do):
/// - Android 11+ (SDK 30+): scoped storage hides dot-folders, so
///   MANAGE_EXTERNAL_STORAGE ("All files access") is required.
/// - Android 10 and below: classic READ/WRITE_EXTERNAL_STORAGE suffices.
library;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'status_models.dart';
import 'status_scanner.dart';

class StatusRepository {
  static const _channel =
      MethodChannel('com.aatishstudio.vidbaaz/media');

  final StatusScanner _scanner = StatusScanner();

  /// Native storage root, e.g. `/storage/emulated/0`.
  Future<String> storageRoot() async =>
      (await _channel.invokeMethod<String>('getStorageRoot'))!;

  Future<int> sdkInt() async =>
      (await _channel.invokeMethod<int>('getSdkInt'))!;

  /// True when the app can read `.Statuses` folders.
  Future<bool> hasAccess() async {
    final sdk = await sdkInt();
    if (sdk >= 30) {
      return Permission.manageExternalStorage.isGranted;
    }
    return Permission.storage.isGranted;
  }

  /// Requests the needed permission. On Android 11+ this opens the
  /// "All files access" settings page (system UI, one toggle).
  Future<bool> requestAccess() async {
    final sdk = await sdkInt();
    if (sdk >= 30) {
      final status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    }
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  /// Opens the app's "All files access" settings page directly (fallback
  /// shown when the user denied the request and needs manual steps).
  Future<void> openAllFilesAccessSettings() =>
      _channel.invokeMethod('openAllFilesAccessSettings');

  Future<List<StatusItem>> loadStatuses() async =>
      _scanner.scan(await storageRoot());

  Future<List<StatusApp>> availableApps() async =>
      _scanner.availableApps(await storageRoot());

  /// Saves [item] into `Pictures/VidBaaz` and triggers a
  /// media scan so gallery apps show it immediately.
  Future<String> save(StatusItem item) async {
    final galleryDir = '${await storageRoot()}/Pictures/VidBaaz';
    final saved = _scanner.saveToGallery(item, galleryDir);
    await _channel.invokeMethod('scanFile', {'path': saved});
    return saved;
  }
}
