/// Downloader tab: paste a link -> resolve -> download with progress.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../downloader/downloader_engine.dart';
import '../downloader/link_classifier.dart';
import '../media/media_scan.dart';
import 'fb_browser_screen.dart';

enum _DlState { idle, resolving, downloading, done, error }

class DownloaderTab extends StatefulWidget {
  const DownloaderTab({super.key});

  @override
  State<DownloaderTab> createState() => _DownloaderTabState();
}

class _DownloaderTabState extends State<DownloaderTab> {
  final _controller = TextEditingController();
  final _engine = DownloaderEngine();
  _DlState _state = _DlState.idle;
  double _progress = 0;
  String _message = '';

  @override
  void dispose() {
    _controller.dispose();
    _engine.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _controller.text = data!.text!.trim();
    }
  }

  Future<void> _openInBrowser(String url) async {
    setState(() {
      _state = _DlState.idle;
      _message = 'Facebook blocked the direct download, so the video '
          'was opened in the in-app browser.';
    });
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FbBrowserScreen(pageUrl: url)),
    );
  }

  Future<void> _download() async {
    final link = _controller.text.trim();
    if (link.isEmpty) {
      setState(() {
        _state = _DlState.error;
        _message = 'Paste a video link first.';
      });
      return;
    }
    final classified = LinkClassifier().classify(link);
    // Facebook share links can never be fetched over HTTP (Facebook
    // answers 400 to non-browsers) — open them in the in-app browser,
    // where they resolve to the video page like in Chrome.
    if (classified.kind == LinkKind.facebook &&
        DownloaderEngine.isFacebookShareLink(classified.url)) {
      await _openInBrowser(classified.url);
      return;
    }
    setState(() {
      _state = _DlState.resolving;
      _progress = 0;
      _message = 'Finding video…';
    });
    try {
      final direct = await _engine.resolve(link);
      if (!mounted) return;
      setState(() {
        _state = _DlState.downloading;
        _message = 'Downloading…';
      });
      final saved = await _engine.download(
        direct,
        '/storage/emulated/0/Download/VidBaaz',
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // Issue #26: scan the file so Gallery apps see it at once
      // (without this, only the in-app Saved tab lists it).
      await MediaScan.scanFile(saved);
      if (!mounted) return;
      setState(() {
        _state = _DlState.done;
        _progress = 1;
        _message = 'Saved: ${saved.split('/').last}';
      });
    } on ResolveException catch (e) {
      if (!mounted) return;
      // Any Facebook failure falls back to the in-app browser — the
      // video page there usually exposes the file even when HTTP was
      // blocked.
      if (classified.kind == LinkKind.facebook) {
        await _openInBrowser(classified.url);
        return;
      }
      setState(() {
        _state = _DlState.error;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _DlState.error;
        _message = 'Could not download this link. Check your connection '
            'and try a public video link.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Paste a video link',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Facebook and TikTok public videos, plus direct video links supported.',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'https://…',
                    prefixIcon: Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _paste,
                icon: const Icon(Icons.content_paste),
                tooltip: 'Paste',
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed:
                _state == _DlState.resolving || _state == _DlState.downloading
                    ? null
                    : _download,
            icon: const Icon(Icons.download),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Download', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 24),
          if (_state == _DlState.resolving ||
              _state == _DlState.downloading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
          ],
          if (_message.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _state == _DlState.error
                    ? Colors.red.shade900.withValues(alpha: 0.5)
                    : _state == _DlState.done
                        ? Colors.green.shade900.withValues(alpha: 0.5)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _message,
                style: const TextStyle(height: 1.4),
              ),
            ),
          if (_state == _DlState.done) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() {
                _state = _DlState.idle;
                _controller.clear();
                _message = '';
                _progress = 0;
              }),
              icon: const Icon(Icons.refresh),
              label: const Text('Download another'),
            ),
          ],
        ],
      ),
    );
  }
}
