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

class FbBrowserScreen extends StatefulWidget {
  final String pageUrl;
  const FbBrowserScreen({super.key, required this.pageUrl});

  @override
  State<FbBrowserScreen> createState() => _FbBrowserScreenState();
}

class _FbBrowserScreenState extends State<FbBrowserScreen> {
  late final WebViewController _controller;
  final _engine = DownloaderEngine();
  final _cookieManager = WebViewCookieManager();

  String? _videoUrl;
  bool _downloading = false;
  bool _saved = false;
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
    if (_videoUrl != null) return;
    _extractTimer?.cancel();
    _extractTimer = Timer(const Duration(milliseconds: 800), _tryExtract);
  }

  Future<void> _tryExtract() async {
    if (!mounted || _videoUrl != null) return;
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
            child: const Text(
              'Let the video load. If a Facebook login popup appears, '
              'just close it (tap X) — no login is needed.',
              style: TextStyle(color: Colors.black87, fontSize: 13),
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
                      if (_videoUrl == null) ...[
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
