/// Downloader tab: paste a link -> resolve -> download with progress.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../downloader/downloader_engine.dart';

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

  /// The pasted link, kept when it is a Facebook share link so the user
  /// can open it in the Facebook app and copy the full video link.
  String? _shareLink;

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

  Future<void> _download() async {
    final link = _controller.text.trim();
    if (link.isEmpty) {
      setState(() {
        _state = _DlState.error;
        _message = 'Paste a video link first.';
      });
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
      if (!mounted) return;
      setState(() {
        _state = _DlState.done;
        _progress = 1;
        _message = 'Saved: ${saved.split('/').last}';
      });
    } on ResolveException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _DlState.error;
        _message = e.message;
        // Facebook share links can't be resolved by any app — keep the
        // link so we can offer "Open in Facebook app".
        _shareLink =
            e.message.contains('share link') ? _controller.text.trim() : null;
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
          if (_shareLink != null && _state == _DlState.error) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.tryParse(_shareLink!);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Open in Facebook app'),
              ),
            ),
          ],
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
