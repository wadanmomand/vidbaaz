/// Client-side video resolver + download manager.
///
/// No backend: Facebook public videos are resolved by fetching the mobile
/// page HTML and extracting the `og:video` / `hd_src` MP4 URL. Direct media
/// links are verified by content-type before saving.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'link_classifier.dart';

class ResolveException implements Exception {
  final String message;
  ResolveException(this.message);
  @override
  String toString() => 'ResolveException: $message';
}

class DownloaderEngine {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

  final http.Client _client;
  DownloaderEngine({http.Client? client}) : _client = client ?? http.Client();

  void dispose() => _client.close();

  LinkKind _lastKind = LinkKind.directMedia;

  /// The normalized page URL from the last successful resolve — used to
  /// re-resolve once if a download gets rejected (TikTok play URLs can
  /// expire or be region-pinned).
  String? _lastPageUrl;

  /// Resolves a pasted link to a direct MP4 URL (or throws [ResolveException]).
  Future<String> resolve(String rawLink) async {
    final link = LinkClassifier().classify(rawLink);
    _lastKind = link.kind;
    _lastPageUrl = link.kind == LinkKind.tiktok ? link.url : null;
    switch (link.kind) {
      case LinkKind.unsupported:
        throw ResolveException(link.reason);
      case LinkKind.directMedia:
        final head = await _client.head(Uri.parse(link.url),
            headers: {'User-Agent': _ua});
        final ct = head.headers['content-type'] ?? '';
        if (head.statusCode == 200 && ct.startsWith('video/')) {
          return link.url;
        }
        // Some hosts reject HEAD — fall through and try GET resolution.
        return _resolveFromPage(link.url);
      case LinkKind.facebook:
        return _resolveFacebook(link.url);
      case LinkKind.tiktok:
        return _resolveTikTok(link.url);
    }
  }

  Future<String> _resolveFacebook(String pageUrl) async {
    // Facebook /share/r/ and /share/v/ links are app-share intents: Facebook
    // returns HTTP 400 for them to any non-logged-in client, so they can
    // never be resolved by an app. Tell the user how to get a working link.
    if (pageUrl.contains('/share/')) {
      throw ResolveException(
          'This is a Facebook share link, which Facebook blocks for apps. '
          'Open it in the Facebook app, open the video, tap Share and copy '
          'the full video link instead.');
    }
    // Try the original URL first (follows redirects), then the mobile and
    // desktop variants — whichever page exposes the MP4 wins.
    final candidates = <String>[
      pageUrl,
      mobileFacebookUrl(pageUrl),
      pageUrl.replaceFirstMapped(
        RegExp(r'^(https?://)(www\.|m\.)?'),
        (m) => '${m.group(1)}www.',
      ),
    ];
    for (final url in candidates.toSet()) {
      final res = await _client.get(Uri.parse(url),
          headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) continue;
      final direct = extractMp4FromHtml(res.body);
      if (direct != null) return direct;
    }
    throw ResolveException(
        'Could not open that Facebook link. It may be private, a live '
        'stream, or Facebook may be blocking it right now.');
  }

  /// Resolves a TikTok link via the video page's embedded JSON
  /// (`__UNIVERSAL_DATA_FOR_REHYDRATION__` -> video -> playAddr).
  Future<String> _resolveTikTok(String pageUrl) async {
    final res = await _client.get(Uri.parse(pageUrl),
        headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ResolveException(
          'Could not open that TikTok link (HTTP ${res.statusCode}).');
    }
    final direct = extractTikTokMp4(res.body);
    if (direct == null) {
      throw ResolveException(
          'No downloadable video found — it may be private or removed.');
    }
    return direct;
  }

  /// Extracts the MP4 play URL from a TikTok video page's HTML.
  /// Public for tests.
  static String? extractTikTokMp4(String html) {
    final m = RegExp(r'"playAddr"\s*:\s*"((?:[^"\\]|\\.)*)"')
        .firstMatch(html);
    if (m == null) return null;
    final url = _unescapeJsonString(m.group(1)!);
    return url.startsWith('http') ? url : null;
  }

  /// Decodes \uXXXX escapes and \/ sequences found in embedded JSON.
  static String _unescapeJsonString(String s) {
    return s
        .replaceAllMapped(
            RegExp(r'\\u([0-9a-fA-F]{4})'),
            (m) =>
                String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
        .replaceAll(r'\/', '/')
        .replaceAll(r'\"', '"');
  }

  /// Builds the fetch URL for a Facebook link. Public for tests.
  ///
  /// The mobile (m.facebook.com) page exposes the MP4 in its HTML far more
  /// reliably than www. Short fb.watch links are left untouched so the
  /// HTTP client can follow their redirect to the real page.
  static String mobileFacebookUrl(String pageUrl) {
    final host = Uri.parse(pageUrl).host.toLowerCase();
    if (!host.contains('facebook.com')) return pageUrl;
    return pageUrl.replaceFirstMapped(
      RegExp(r'^(https?://)(www\.|m\.)?'),
      (m) => '${m.group(1)}m.',
    );
  }

  Future<String> _resolveFromPage(String pageUrl) async {
    final res = await _client.get(Uri.parse(pageUrl),
        headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ResolveException('Could not open that link.');
    }
    final ct = res.headers['content-type'] ?? '';
    if (ct.startsWith('video/')) return pageUrl;
    final direct = extractMp4FromHtml(res.body);
    if (direct == null) {
      throw ResolveException('No downloadable video found at that link.');
    }
    return direct;
  }

  /// Extracts the best MP4 URL from page HTML. Public for tests.
  ///
  /// Prefers `og:video:secure_url`, then `hd_src` (Facebook), then `sd_src`,
  /// then `og:video`.
  static String? extractMp4FromHtml(String html) {
    String unescape(String s) =>
        s.replaceAll(r'\/', '/').replaceAll('&amp;', '&');

    final ogSecure = RegExp(
        r'''<meta[^>]+property=["']og:video:secure_url["'][^>]+content=["']([^"']+)''',
        caseSensitive: false);
    final ogVideo = RegExp(
        r'''<meta[^>]+property=["']og:video["'][^>]+content=["']([^"']+)''',
        caseSensitive: false);
    final hdSrc = RegExp(r'"hd_src"\s*:\s*"([^"]+)"');
    final sdSrc = RegExp(r'"sd_src"\s*:\s*"([^"]+)"');

    for (final re in [ogSecure, hdSrc, ogVideo, sdSrc]) {
      final m = re.firstMatch(html);
      if (m != null) {
        final url = unescape(m.group(1)!);
        if (url.startsWith('http')) return url;
      }
    }
    return null;
  }

  /// Headers for the video file request. TikTok's CDN rejects requests
  /// without the Referer (HTTP 403), so it is always sent for TikTok.
  Map<String, String> _fileHeaders() {
    final h = <String, String>{
      'User-Agent': _ua,
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    if (_lastKind == LinkKind.tiktok) {
      h['Referer'] = 'https://www.tiktok.com/';
    }
    return h;
  }

  Future<http.StreamedResponse> _sendFileRequest(String mediaUrl) {
    final req = http.Request('GET', Uri.parse(mediaUrl))
      ..headers.addAll(_fileHeaders());
    return _client.send(req).timeout(const Duration(seconds: 30));
  }

  /// Downloads [mediaUrl] into [saveDir], reporting 0..1 progress.
  /// Returns the saved file path.
  Future<String> download(
    String mediaUrl,
    String saveDir, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = Directory(saveDir)..createSync(recursive: true);
    final uri = Uri.parse(mediaUrl);
    final name = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last.split('?').first
        : 'video.mp4';
    var target =
        '${dir.path}/${name.isEmpty ? 'video' : name}${name.contains('.') ? '' : '.mp4'}';
    if (File(target).existsSync()) {
      target =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${target.split('/').last}';
    }

    var streamed = await _sendFileRequest(mediaUrl);
    if ((streamed.statusCode == 401 || streamed.statusCode == 403) &&
        _lastKind == LinkKind.tiktok &&
        _lastPageUrl != null) {
      // The play URL was rejected — these URLs expire and can be
      // region-pinned. Re-resolve once for a fresh URL and retry.
      try {
        final fresh = await resolve(_lastPageUrl!);
        streamed = await _sendFileRequest(fresh);
      } on ResolveException {
        // Keep the original 403 response handling below.
      }
    }
    if (streamed.statusCode != 200) {
      if (_lastKind == LinkKind.tiktok) {
        throw ResolveException(
            'TikTok blocked this download right now. Wait a minute and try '
            'again — or copy the link from inside the TikTok app.');
      }
      throw ResolveException('Download failed (HTTP ${streamed.statusCode}).');
    }
    final total = streamed.contentLength ?? -1;
    final file = File(target).openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        file.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await file.close();
    }
    onProgress?.call(1.0);
    return target;
  }
}
