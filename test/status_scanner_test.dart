import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vid_baaz/status/status_models.dart';
import 'package:vid_baaz/status/status_scanner.dart';

void main() {
  late Directory tmp;
  late StatusScanner scanner;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('status_test');
    scanner = StatusScanner();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Directory statusDir(List<String> parts) {
    final d = Directory('${tmp.path}/${parts.join('/')}')..createSync(recursive: true);
    return d;
  }

  File touch(Directory dir, String name, {int size = 10}) {
    final f = File('${dir.path}/$name');
    f.writeAsBytesSync(List.filled(size, 1));
    return f;
  }

  test('finds WhatsApp .Statuses media, newest first, skips junk', () {
    final dir = statusDir(['WhatsApp', 'Media', '.Statuses']);
    touch(dir, 'old.jpg');
    sleep(const Duration(milliseconds: 20));
    touch(dir, 'new.mp4');
    touch(dir, '.nomedia');
    touch(dir, 'note.txt');
    touch(dir, 'empty.jpg', size: 0);

    final items = scanner.scan(tmp.path);
    expect(items.map((i) => i.fileName).toList(), ['new.mp4', 'old.jpg']);
    expect(items.first.isVideo, isTrue);
    expect(items.first.app, StatusApp.whatsapp);
    expect(items.last.isVideo, isFalse);
  });

  test('finds Android 11+ scoped path and Business app', () {
    statusDir(['Android', 'media', 'com.whatsapp', 'WhatsApp', 'Media', '.Statuses'])
        .createSync(recursive: true);
    final biz = statusDir(
        ['Android', 'media', 'com.whatsapp.w4b', 'WhatsApp Business', 'Media', '.Statuses']);
    touch(biz, 'biz.png');

    final items = scanner.scan(tmp.path);
    expect(items.length, 1);
    expect(items.first.app, StatusApp.whatsappBusiness);
    // Both the (empty) WhatsApp scoped dir and the Business dir exist.
    expect(scanner.availableApps(tmp.path),
        [StatusApp.whatsapp, StatusApp.whatsappBusiness]);
  });

  test('saveToGallery copies file and dedupes names', () {
    final dir = statusDir(['WhatsApp', 'Media', '.Statuses']);
    touch(dir, 'pic.jpg');
    final item = scanner.scan(tmp.path).single;

    final gallery = '${tmp.path}/gallery';
    final first = scanner.saveToGallery(item, gallery);
    final second = scanner.saveToGallery(item, gallery);
    expect(first, isNot(equals(second)));
    expect(File(first).existsSync(), isTrue);
    expect(File(second).existsSync(), isTrue);
  });
}
