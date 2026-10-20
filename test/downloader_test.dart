import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vid_baaz/downloader/downloader_engine.dart';
import 'package:vid_baaz/downloader/link_classifier.dart';
import 'package:vid_baaz/ui/fb_browser_screen.dart';

void main() {
  final classifier = LinkClassifier();

  group('LinkClassifier', () {
    test('direct mp4 link', () {
      final c = classifier.classify('https://example.com/v/clip.mp4');
      expect(c.kind, LinkKind.directMedia);
    });

    test('facebook link', () {
      final c = classifier.classify('https://www.facebook.com/watch/?v=123');
      expect(c.kind, LinkKind.facebook);
    });

    test('fb.watch short link', () {
      final c = classifier.classify('fb.watch/abc123');
      expect(c.kind, LinkKind.facebook);
      expect(c.url.startsWith('https://'), isTrue);
    });

    test('youtube unsupported with Play-policy reason', () {
      final c = classifier.classify('https://youtu.be/abc');
      expect(c.kind, LinkKind.unsupported);
      expect(c.reason, contains('Play'));
    });

    test('instagram unsupported, tiktok supported', () {
      expect(classifier.classify('https://instagram.com/reel/x').kind,
          LinkKind.unsupported);
      expect(classifier.classify('https://tiktok.com/@u/video/1').kind,
          LinkKind.tiktok);
      expect(
          classifier
              .classify('https://www.tiktok.com/t/ZTfjYgphP/')
              .kind,
          LinkKind.tiktok);
    });

    test('extractTikTokMp4 decodes playAddr escapes', () {
      const html =
          r'{"playAddr":"https:\/\/v16-webapp-prime.us.tiktok.com\/video\/x.mp4?mime_type=video_mp4"}';
      expect(
        DownloaderEngine.extractTikTokMp4(html),
        'https://v16-webapp-prime.us.tiktok.com/video/x.mp4?mime_type=video_mp4',
      );
    });

    test('extractTikTokMp4 returns null when absent', () {
      expect(DownloaderEngine.extractTikTokMp4('<html>no video</html>'),
          isNull);
    });

    test('empty and garbage input', () {
      expect(classifier.classify('').kind, LinkKind.unsupported);
      expect(classifier.classify('not a link').kind, LinkKind.unsupported);
    });
  });

  group('mobileFacebookUrl', () {
    test('www.facebook.com -> m.facebook.com', () {
      expect(
        DownloaderEngine.mobileFacebookUrl(
            'https://www.facebook.com/share/r/1KjYyLxhUf/'),
        'https://m.facebook.com/share/r/1KjYyLxhUf/',
      );
    });

    test('bare facebook.com gets m. added', () {
      expect(
        DownloaderEngine.mobileFacebookUrl('https://facebook.com/watch?v=1'),
        'https://m.facebook.com/watch?v=1',
      );
    });

    test('already-mobile URL stays the same', () {
      expect(
        DownloaderEngine.mobileFacebookUrl('https://m.facebook.com/watch?v=1'),
        'https://m.facebook.com/watch?v=1',
      );
    });

    test('fb.watch short link left untouched for redirect', () {
      expect(
        DownloaderEngine.mobileFacebookUrl('https://fb.watch/abc123/'),
        'https://fb.watch/abc123/',
      );
    });
  });

  group('resolve', () {
    test('facebook share link throws browser-needed error, no crash',
        () async {
      final engine = DownloaderEngine();
      expect(
        () => engine.resolve('https://facebook.com/share/r/abc123/'),
        throwsA(isA<ResolveException>().having(
            (e) => e.message, 'message', contains('in-app browser'))),
      );
      engine.dispose();
    });

    test('browser blocks app deep-link schemes (issue #18)', () {
      expect(
          FbBrowserScreen.shouldBlockNavigation(
              'fb://fullscreen_video/2602442030183424?loop=false'),
          isTrue);
      expect(
          FbBrowserScreen.shouldBlockNavigation(
              'intent://www.facebook.com/reel/1#Intent;scheme=https;end'),
          isTrue);
      expect(
          FbBrowserScreen.shouldBlockNavigation(
              'https://www.facebook.com/reel/2602442030183424'),
          isFalse);
      expect(
          FbBrowserScreen.shouldBlockNavigation(
              'http://m.facebook.com/watch/?v=1'),
          isFalse);
    });

    test('isFacebookShareLink detects share urls (issue #15)', () {
      expect(
          DownloaderEngine.isFacebookShareLink(
              'https://www.facebook.com/share/v/1DFn1DD3vL/'),
          isTrue);
      expect(
          DownloaderEngine.isFacebookShareLink(
              'https://www.facebook.com/share/r/abc/'),
          isTrue);
      expect(
          DownloaderEngine.isFacebookShareLink(
              'https://www.facebook.com/watch/?v=123'),
          isFalse);
      expect(
          DownloaderEngine.isFacebookShareLink(
              'https://www.tiktok.com/t/abc/'),
          isFalse);
    });

    test('setExternalCookies are sent on the file request', () async {
      final sent = <http.BaseRequest>[];
      final client = MockClient((req) async {
        sent.add(req);
        if (req.url.host.contains('facebook.com')) {
          return http.Response(
              '<meta property="og:video:secure_url" content="https://cdn.example.com/v.mp4">',
              200);
        }
        return http.Response('bytes', 200,
            headers: {'content-type': 'video/mp4', 'content-length': '5'});
      });
      final engine = DownloaderEngine(client: client);
      engine.setExternalCookies(
          LinkKind.facebook, {'c_user': '123', 'xs': 'abc'});
      final direct =
          await engine.resolve('https://www.facebook.com/watch/?v=1');
      final dir = await Directory.systemTemp.createTemp('vb');
      final saved = await engine.download(direct, dir.path);
      expect(File(saved).existsSync(), isTrue);
      final fileReq =
          sent.firstWhere((r) => r.url.host.contains('cdn.example.com'));
      expect(fileReq.headers['Cookie'], contains('c_user=123'));
      expect(fileReq.headers['Cookie'], contains('xs=abc'));
      engine.dispose();
    });

    test('facebook video page resolves via candidate pages', () async {
      final requested = <String>[];
      final client = MockClient((req) async {
        requested.add(req.url.toString());
        return http.Response(
            '<meta property="og:video:secure_url" content="https://cdn.example.com/v.mp4">',
            200);
      });
      final engine = DownloaderEngine(client: client);
      expect(
        await engine.resolve('https://www.facebook.com/watch?v=1'),
        'https://cdn.example.com/v.mp4',
      );
      // First candidate tried is the original URL.
      expect(requested.first, contains('facebook.com/watch'));
      engine.dispose();
    });

    test('facebook page without video throws friendly error', () async {
      final client = MockClient((_) async => http.Response('<html></html>', 200));
      final engine = DownloaderEngine(client: client);
      expect(
        () => engine.resolve('https://www.facebook.com/watch?v=1'),
        throwsA(isA<ResolveException>()),
      );
      engine.dispose();
    });
  });

  group('extractMp4FromHtml', () {
    test('prefers og:video:secure_url', () {
      const html = '''
        <meta property="og:video" content="http://low.mp4">
        <meta property="og:video:secure_url" content="https://cdn.example.com/hi.mp4">
      ''';
      expect(DownloaderEngine.extractMp4FromHtml(html),
          'https://cdn.example.com/hi.mp4');
    });

    test('falls back to hd_src JSON', () {
      const html = r'{"hd_src":"https:\/\/cdn.example.com\/hd.mp4","sd_src":"x"}';
      expect(DownloaderEngine.extractMp4FromHtml(html),
          'https://cdn.example.com/hd.mp4');
    });

    test('falls back to sd_src when no hd', () {
      const html = r'{"sd_src":"https:\/\/cdn.example.com\/sd.mp4"}';
      expect(DownloaderEngine.extractMp4FromHtml(html),
          'https://cdn.example.com/sd.mp4');
    });

    test('returns null when nothing found', () {
      expect(DownloaderEngine.extractMp4FromHtml('<html>nope</html>'), isNull);
    });

    test('extracts modern playable_url_quality_hd JSON (issue #14)', () {
      const html =
          r'{"playable_url":"https:\/\/video.fbcdn.net\/sd.mp4?x=1","playable_url_quality_hd":"https:\/\/video.fbcdn.net\/hd.mp4?x=1\u0026y=2"}';
      expect(DownloaderEngine.extractMp4FromHtml(html),
          'https://video.fbcdn.net/hd.mp4?x=1&y=2');
    });

    test('extracts browser_native_hd_url when no playable_url', () {
      const html =
          r'{"browser_native_hd_url":"https:\/\/video.fbcdn.net\/native.mp4"}';
      expect(DownloaderEngine.extractMp4FromHtml(html),
          'https://video.fbcdn.net/native.mp4');
    });

    test('falls back to playable_url (sd) when no hd pattern', () {
      const html =
          r'{"playable_url":"https:\/\/video.fbcdn.net\/sd.mp4"}';
      expect(DownloaderEngine.extractMp4FromHtml(html),
          'https://video.fbcdn.net/sd.mp4');
    });
  });

group('tiktok download robustness (issue #12)', () {
  const pageHtml =
      r'<html>"playAddr":"https:\/\/cdn.example.com\/vid1.mp4","other":"x"</html>';

  test('file request carries Referer for tiktok and succeeds', () async {
    final sent = <http.BaseRequest>[];
    final client = MockClient((req) async {
      sent.add(req);
      if (req.url.host.contains('tiktok.com')) {
        return http.Response(pageHtml, 200);
      }
      return http.Response('bytes', 200,
          headers: {'content-type': 'video/mp4', 'content-length': '5'});
    });
    final engine = DownloaderEngine(client: client);
    final direct = await engine.resolve('https://www.tiktok.com/t/abc/');
    expect(direct, 'https://cdn.example.com/vid1.mp4');
    final dir = await Directory.systemTemp.createTemp('vb');
    final saved = await engine.download(direct, dir.path);
    expect(File(saved).existsSync(), isTrue);
    final fileReq = sent.firstWhere(
        (r) => r.url.host.contains('cdn.example.com'));
    expect(fileReq.headers['Referer'], 'https://www.tiktok.com/');
    engine.dispose();
  });

  test('403 on file -> re-resolves once and retries with fresh URL', () async {
    var pageHits = 0;
    final fileHits = <String>[];
    final client = MockClient((req) async {
      if (req.url.host.contains('tiktok.com')) {
        pageHits++;
        final url = pageHits == 1
            ? 'https://cdn.example.com/old.mp4'
            : 'https://cdn.example.com/new.mp4';
        return http.Response(
            '<html>"playAddr":"${url.replaceAll('/', r'\/')}","x":"y"</html>',
            200);
      }
      fileHits.add(req.url.toString());
      if (req.url.toString().contains('old.mp4')) {
        return http.Response('denied', 403);
      }
      return http.Response('bytes', 200,
          headers: {'content-type': 'video/mp4', 'content-length': '5'});
    });
    final engine = DownloaderEngine(client: client);
    final direct = await engine.resolve('https://www.tiktok.com/t/abc/');
    expect(direct, contains('old.mp4'));
    final dir = await Directory.systemTemp.createTemp('vb');
    final saved = await engine.download(direct, dir.path);
    expect(File(saved).existsSync(), isTrue);
    expect(fileHits, ['https://cdn.example.com/old.mp4',
      'https://cdn.example.com/new.mp4']);
    expect(pageHits, 2); // initial resolve + one re-resolve
    engine.dispose();
  });

  test('persistent 403 gives friendly tiktok message', () async {
    final client = MockClient((req) async {
      if (req.url.host.contains('tiktok.com')) {
        return http.Response(pageHtml, 200);
      }
      return http.Response('denied', 403);
    });
    final engine = DownloaderEngine(client: client);
    final direct = await engine.resolve('https://www.tiktok.com/t/abc/');
    final dir = await Directory.systemTemp.createTemp('vb');
    expect(
      () => engine.download(direct, dir.path),
      throwsA(isA<ResolveException>().having(
          (e) => e.message, 'message', contains('TikTok blocked'))),
    );
    engine.dispose();
  });
});

group('tiktok session cookies (issue #13)', () {
  const pageHtml =
      r'<html>"playAddr":"https:\/\/cdn.example.com\/vid1.mp4","other":"x"</html>';
  const setCookie =
      'ttwid=abc123; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/, '
      'tt_chain_token=xyz789; Path=/; HttpOnly, msToken=tok42; Path=/';

  test('parseSetCookie splits combined header, ignores Expires commas',
      () {
    final parsed = DownloaderEngine.parseSetCookie(setCookie);
    expect(parsed, {
      'ttwid': 'abc123',
      'tt_chain_token': 'xyz789',
      'msToken': 'tok42',
    });
    expect(DownloaderEngine.parseSetCookie(null), isEmpty);
    expect(DownloaderEngine.parseSetCookie(''), isEmpty);
  });

  test('file request carries the page session cookies', () async {
    final sent = <http.BaseRequest>[];
    final client = MockClient((req) async {
      sent.add(req);
      if (req.url.host.contains('tiktok.com')) {
        return http.Response(pageHtml, 200,
            headers: {'set-cookie': setCookie});
      }
      return http.Response('bytes', 200,
          headers: {'content-type': 'video/mp4', 'content-length': '5'});
    });
    final engine = DownloaderEngine(client: client);
    final direct = await engine.resolve('https://www.tiktok.com/t/abc/');
    final dir = await Directory.systemTemp.createTemp('vb');
    final saved = await engine.download(direct, dir.path);
    expect(File(saved).existsSync(), isTrue);
    final fileReq =
        sent.firstWhere((r) => r.url.host.contains('cdn.example.com'));
    expect(fileReq.headers['Cookie'], contains('ttwid=abc123'));
    expect(fileReq.headers['Cookie'], contains('tt_chain_token=xyz789'));
    engine.dispose();
  });

  test('akamai simulation: CDN 403s without cookie, serves with cookie',
      () async {
    final client = MockClient((req) async {
      if (req.url.host.contains('tiktok.com')) {
        return http.Response(pageHtml, 200,
            headers: {'set-cookie': setCookie});
      }
      // Like Akamai: no session cookie -> Access Denied.
      if ((req.headers['Cookie'] ?? '').contains('ttwid=abc123')) {
        return http.Response('bytes', 200,
            headers: {'content-type': 'video/mp4', 'content-length': '5'});
      }
      return http.Response('Access Denied', 403);
    });
    final engine = DownloaderEngine(client: client);
    final direct = await engine.resolve('https://www.tiktok.com/t/abc/');
    final dir = await Directory.systemTemp.createTemp('vb');
    final saved = await engine.download(direct, dir.path);
    expect(File(saved).existsSync(), isTrue);
    expect(await File(saved).readAsString(), 'bytes');
    engine.dispose();
  });
});

}
