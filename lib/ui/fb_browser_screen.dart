/// In-app browser for Facebook links.
///
/// Facebook answers HTTP 400 to every non-browser client for share links
/// (verified live 2026-10-20), but a real browser resolves them to the
/// video page — logged out, no login needed. This screen loads the pasted
/// Facebook link in a WebView (Chromium), reads the loaded page's HTML,
/// extracts the video file URL with the same extractor the HTTP path
/// uses, and downloads it with the engine (cookies from the WebView
/// session merged in). The user never has to log in; if Facebook shows
/// a login popup they can simply close it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../downloader/downloader_engine.dart';
import '../downloader/link_classifier.dart';
import '../media/media_scan.dart';

class FbBrowserScreen extends StatefulWidget {
  final String pageUrl;
  const FbBrowserScreen({super.key, required this.pageUrl});

  /// Facebook pages try to bounce mobile browsers into the Facebook app
  /// via non-web schemes (`fb://…`, `intent://…`). A WebView cannot open
  /// those and replaces the whole page with ERR_UNKNOWN_URL_SCHEME —
  /// which destroyed the video page before extraction could run
  /// (issue #18, device screenshot 2026-10-20). Only http/https
  /// navigations may proceed. Public for tests.
  static bool shouldBlockNavigation(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return true;
    return uri.scheme != 'http' && uri.scheme != 'https';
  }

  /// Facebook sometimes answers a video with a full login page instead
  /// of the video (issue #25). That is NOT a closable popup: the whole
  /// page redirects to login, so there is no X and no file will ever
  /// appear behind it. Detect it so the UI can say so honestly instead
  /// of looping "file not found, tap Retry". Public for tests.
  static bool isFacebookLoginUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host != 'facebook.com' &&
        !host.endsWith('.facebook.com') &&
        host != 'm.facebook.com') {
      return false;
    }
    final path = uri.path.toLowerCase();
    return path == '/login' ||
        path.startsWith('/login/') ||
        path.contains('login.php') ||
        path.startsWith('/checkpoint/');
  }

  @override
  State<FbBrowserScreen> createState() => _FbBrowserScreenState();
}

class _FbBrowserScreenState extends State<FbBrowserScreen> {
  late final WebViewController _controller;
  final _engine = DownloaderEngine();
  final _cookieManager = WebViewCookieManager();

  String? _videoUrl;
  String _currentUrl = '';
  String _fallbackForUrl = '';
  bool _downloading = false;
  bool _saved = false;
  bool _loginWall = false;
  double _progress = 0;
  String _status = 'Loading the Facebook page…';
  int _extractAttempts = 0;
  Timer? _extractTimer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36')
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          // Keep the WebView on the video page: block Facebook's
          // app-deep-link bounces (fb://, intent://, …).
          if (FbBrowserScreen.shouldBlockNavigation(request.url)) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onUrlChange: (change) {
          if (change.url != null) {
            _currentUrl = change.url!;
            // A login redirect kills extraction: stop retrying and say
            // so instead of the misleading "file not found, tap Retry".
            final wall =
                FbBrowserScreen.isFacebookLoginUrl(change.url!);
            if (wall && !_loginWall) {
              _extractTimer?.cancel();
              setState(() {
                _loginWall = true;
                _status = 'This video is behind a Facebook login wall, '
                    'so it cannot be downloaded without logging in. '
                    'VidBaaz never asks for your login.';
              });
            }
          }
        },
        onPageFinished: (_) => _scheduleExtraction(),
      ))
      ..loadRequest(Uri.parse(widget.pageUrl));
  }

  @override
  void dispose() {
    _extractTimer?.cancel();
    _engine.dispose();
    super.dispose();
  }

  /// The video URL can appear a moment after the page "finishes" (the
  /// player payload renders late), so extraction retries a few times.
  void _scheduleExtraction() {
    if (_videoUrl != null || _loginWall) return;
    _extractTimer?.cancel();
    _extractTimer = Timer(const Duration(milliseconds: 800), _tryExtract);
  }

  Future<void> _tryExtract() async {
    if (!mounted || _videoUrl != null || _loginWall) return;
    _extractAttempts++;
    try {
      final raw = await _controller
          .runJavaScriptReturningResult('document.documentElement.outerHTML');
      var html = raw.toString();
      // Android returns a JSON-encoded string; decode when quoted.
      if (html.startsWith('"')) {
        final decoded = jsonDecode(html);
        if (decoded is String) html = decoded;
      }
      final found = DownloaderEngine.extractMp4FromHtml(html);
      if (found != null) {
        setState(() {
          _videoUrl = found;
          _status = 'Video found — tap Download.';
        });
        return;
      }
    } catch (_) {
      // Page still settling; retry below.
    }
    // Fallback: once the browser has resolved the share link to the real
    // video page, the engine's HTTP path (3 page variants incl. desktop
    // UA) plus this session's cookies may expose the file even when the
    // WebView's own HTML does not.
    if (_fallbackForUrl != _currentUrl &&
        _currentUrl.contains('facebook.com') &&
        !DownloaderEngine.isFacebookShareLink(_currentUrl)) {
      _fallbackForUrl = _currentUrl;
      try {
        final cookies = await _cookieManager.getCookies(
            domain: Uri.parse(_currentUrl));
        _engine.setExternalCookies(LinkKind.facebook,
            {for (final c in cookies) c.name: c.value});
        final direct = await _engine.resolve(_currentUrl);
        if (!mounted) return;
        setState(() {
          _videoUrl = direct;
          _status = 'Video found — tap Download.';
        });
        return;
      } catch (_) {
        // HTTP path blocked too; keep retrying page extraction.
      }
    }
    if (_extractAttempts < 8) {
      _extractTimer = Timer(const Duration(seconds: 2), _tryExtract);
    } else {
      setState(() {
        _status = 'Video is open but its file was not found yet. '
            'Let it load fully, then tap Retry.';
      });
    }
  }

  Future<void> _download() async {
    if (_videoUrl == null || _downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Downloading…';
    });
    try {
      // Carry the browser session's cookies into the file request.
      final cookies = await _cookieManager.getCookies(
          domain: Uri.parse(widget.pageUrl));
      _engine.setExternalCookies(LinkKind.facebook,
          {for (final c in cookies) c.name: c.value});
      final saved = await _engine.download(
        _videoUrl!,
        '/storage/emulated/0/Download/VidBaaz',
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // Issue #26: tell Android's media scanner about the file, or
      // Gallery never sees it (Saved tab reads the folder directly,
      // Gallery reads MediaStore).
      await MediaScan.scanFile(saved);
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _saved = true;
        _progress = 1;
        _status = 'Saved: ${saved.split('/').last}';
      });
    } on ResolveException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = 'Download failed. Check your connection and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FACEBOOK VIDEO'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload page',
            onPressed: () {
              _extractAttempts = 0;
              _loginWall = false;
              _status = 'Loading the Facebook page…';
              _controller.reload();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.amber.shade100,
            child: Text(
              _loginWall
                  ? 'This video needs a Facebook login to view. '
                      'VidBaaz never asks you to log in — please try '
                      'a different video.'
                  : 'Let the video load. If a Facebook login popup appears, '
                      'just close it (tap X) — no login is needed.',
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_status, style: const TextStyle(height: 1.4)),
                if (_downloading || (_saved && _progress == 1)) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _progress),
                ],
                const SizedBox(height: 12),
                if (_saved)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Saved — check the Saved tab'),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _videoUrl == null || _downloading
                              ? null
                              : _download,
                          icon: const Icon(Icons.download),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('Download this video',
                                style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ),
                      if (_videoUrl == null && !_loginWall) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            _extractAttempts = 0;
                            _tryExtract();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
