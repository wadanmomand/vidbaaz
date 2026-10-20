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

  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  final http.Client _client;
  DownloaderEngine({http.Client? client}) : _client = client ?? http.Client();

  void dispose() => _client.close();

  LinkKind _lastKind = LinkKind.directMedia;

  /// Session cookies captured from resolver page responses, per link kind.
  ///
  /// TikTok's CDN (Akamai) rejects the playAddr file request with 403
  /// unless the cookies the video page set (ttwid, tt_chain_token, …) are
  /// sent with it — verified live 2026-10-20: same playAddr returned 403
  /// without cookies and 206 + MP4 bytes with them (issue #13).
  final Map<LinkKind, Map<String, String>> _sessionCookies = {};

  /// Parses a (possibly combined) `set-cookie` header into name → value.
  /// Public for tests.
  static Map<String, String> parseSetCookie(String? header) {
    final out = <String, String>{};
    if (header == null || header.isEmpty) return out;
    // Split only on commas that start a new cookie (`name=` follows) —
    // Expires dates contain commas that must not split.
    for (final part
        in header.split(RegExp(r",\s*(?=[A-Za-z0-9!#$%&'*+\-.^_`|~]+=)"))) {
      final pair = part.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      out[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
    }
    return out;
  }

  void _captureCookies(LinkKind kind, Map<String, String> headers) {
    final parsed = parseSetCookie(headers['set-cookie']);
    if (parsed.isEmpty) return;
    (_sessionCookies[kind] ??= {}).addAll(parsed);
  }

  /// Merges cookies obtained outside the engine (e.g. from the in-app
  /// Facebook browser's cookie store) into the session jar, so file
  /// requests carry them. Public for the browser screen + tests.
  void setExternalCookies(LinkKind kind, Map<String, String> cookies) {
    if (cookies.isEmpty) return;
    (_sessionCookies[kind] ??= {}).addAll(cookies);
  }

  /// Facebook app-share links (`/share/r/`, `/share/v/`): Facebook answers
  /// HTTP 400 to every non-browser client (verified live 2026-10-20), but
  /// a real browser resolves them to the video page — these must go
  /// through the in-app browser screen, not HTTP. Public for tests.
  static bool isFacebookShareLink(String url) =>
      url.contains('facebook.com/share/');

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
    // Facebook /share/r/ and /share/v/ links: Facebook returns HTTP 400
    // for them to any non-browser client (verified live), so HTTP can
    // never resolve them. The UI routes these to the in-app browser
    // instead; this throw is only a backstop.
    if (pageUrl.contains('/share/')) {
      throw ResolveException(
          'This Facebook link needs the in-app browser to open.');
    }
    // Try the original URL first (follows redirects), then the mobile and
    // desktop variants — whichever page exposes the MP4 wins. The desktop
    // variant is fetched with a desktop UA: its page embeds the modern
    // `playable_url` JSON the extractor reads.
    final candidates = <(String, String)>[
      (pageUrl, _ua),
      (mobileFacebookUrl(pageUrl), _ua),
      (
        pageUrl.replaceFirstMapped(
          RegExp(r'^(https?://)(www\.|m\.)?'),
          (m) => '${m.group(1)}www.',
        ),
        _desktopUa,
      ),
    ];
    final seen = <String>{};
    for (final (url, ua) in candidates) {
      if (!seen.add('$ua|$url')) continue;
      final res = await _client.get(Uri.parse(url),
          headers: {'User-Agent': ua}).timeout(const Duration(seconds: 20));
      _captureCookies(LinkKind.facebook, res.headers);
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
    // The page's session cookies MUST accompany the file request or
    // TikTok's CDN answers 403 (issue #13).
    _captureCookies(LinkKind.tiktok, res.headers);
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
  /// Prefers HD sources. Modern Facebook pages embed the video in JSON as
  /// `playable_url` / `playable_url_quality_hd` / `browser_native_*_url`;
  /// older pages use `og:video` meta tags or `hd_src` / `sd_src`.
  static String? extractMp4FromHtml(String html) {
    String unescape(String s) =>
        _unescapeJsonString(s).replaceAll('&amp;', '&');

    final ogSecure = RegExp(
        r'''<meta[^>]+property=["']og:video:secure_url["'][^>]+content=["']([^"']+)''',
        caseSensitive: false);
    final ogVideo = RegExp(
        r'''<meta[^>]+property=["']og:video["'][^>]+content=["']([^"']+)''',
        caseSensitive: false);
    final playableHd =
        RegExp(r'"playable_url_quality_hd"\s*:\s*"((?:[^"\\]|\\.)*)"');
    final browserHd =
        RegExp(r'"browser_native_hd_url"\s*:\s*"((?:[^"\\]|\\.)*)"');
    final hdSrc = RegExp(r'"hd_src"\s*:\s*"((?:[^"\\]|\\.)*)"');
    final playable = RegExp(r'"playable_url"\s*:\s*"((?:[^"\\]|\\.)*)"');
    final browserSd =
        RegExp(r'"browser_native_sd_url"\s*:\s*"((?:[^"\\]|\\.)*)"');
    final sdSrc = RegExp(r'"sd_src"\s*:\s*"((?:[^"\\]|\\.)*)"');

    for (final re in [
      ogSecure,
      playableHd,
      browserHd,
      hdSrc,
      playable,
      browserSd,
      ogVideo,
      sdSrc,
    ]) {
      final m = re.firstMatch(html);
      if (m != null) {
        final url = unescape(m.group(1)!);
        if (url.startsWith('http')) return url;
      }
    }
    return null;
  }

  /// Headers for the video file request. TikTok's CDN rejects requests
  /// without the Referer (HTTP 403), so it is always sent for TikTok —
  /// along with the session cookies captured from the video page, which
  /// the CDN also requires (issue #13).
  Map<String, String> _fileHeaders() {
    final h = <String, String>{
      'User-Agent': _ua,
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    if (_lastKind == LinkKind.tiktok) {
      h['Referer'] = 'https://www.tiktok.com/';
    }
    final cookies = _sessionCookies[_lastKind];
    if (cookies != null && cookies.isNotEmpty) {
      h['Cookie'] =
          cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
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
