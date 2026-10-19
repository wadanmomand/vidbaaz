/// Full-screen viewer for images and videos.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

class ViewerScreen extends StatefulWidget {
  final String path;
  final VoidCallback? onSave;

  const ViewerScreen.file(this.path, {super.key, this.onSave});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  static const _videoExts = {'.mp4', '.webm', '.mov', '.3gp', '.m4v', '.mkv'};
  VideoPlayerController? _video;

  bool get _isVideo =>
      _videoExts.contains('.${widget.path.split('.').last.toLowerCase()}');

  @override
  void initState() {
    super.initState();
    if (_isVideo) {
      _video = VideoPlayerController.file(File(widget.path))
        ..initialize().then((_) {
          if (mounted) setState(() {});
          _video?.play();
        });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        actions: [
          if (widget.onSave != null)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Save',
              onPressed: () {
                widget.onSave!();
                Navigator.of(context).pop();
              },
            ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () => SharePlus.instance
                .share(ShareParams(files: [XFile(widget.path)])),
          ),
        ],
      ),
      body: Center(
        child: _isVideo ? _videoBody() : Image.file(File(widget.path)),
      ),
    );
  }

  Widget _videoBody() {
    final v = _video;
    if (v == null || !v.value.isInitialized) {
      return const CircularProgressIndicator();
    }
    return GestureDetector(
      onTap: () => setState(
          () => v.value.isPlaying ? v.pause() : v.play()),
      child: AspectRatio(
        aspectRatio: v.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(v),
            if (!v.value.isPlaying)
              const Icon(Icons.play_circle_fill,
                  size: 72, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
