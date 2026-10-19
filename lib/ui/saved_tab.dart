/// Saved tab: everything downloaded/saved by the app, with view/share/delete.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'viewer_screen.dart';

class SavedTab extends StatefulWidget {
  const SavedTab({super.key});

  @override
  State<SavedTab> createState() => SavedTabState();
}

class SavedTabState extends State<SavedTab> {
  static const _roots = [
    '/storage/emulated/0/Pictures/VidBaaz',
    '/storage/emulated/0/Download/VidBaaz',
  ];
  static const _videoExts = {'.mp4', '.webm', '.mov', '.3gp', '.m4v', '.mkv'};

  bool _loading = true;
  List<File> _files = [];

  /// Reloads the file list (called when the tab becomes visible).
  Future<void> refresh() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final files = <File>[];
    for (final root in _roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync()) {
        if (e is File) files.add(e);
      }
    }
    files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  bool _isVideo(File f) =>
      _videoExts.contains('.${f.path.split('.').last.toLowerCase()}');

  Future<void> _delete(File f) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text(f.path.split('/').last),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await f.delete();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_files.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nothing saved yet.\nSave a status or download a video and it will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, height: 1.6),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _files.length,
        itemBuilder: (_, i) {
          final f = _files[i];
          final name = f.path.split('/').last;
          final video = _isVideo(f);
          return Card(
            child: ListTile(
              leading: video
                  ? const Icon(Icons.play_circle_fill,
                      size: 44, color: Colors.white70)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(f,
                          width: 56, height: 56, fit: BoxFit.cover),
                    ),
              title: Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${(f.statSync().size / 1024 / 1024).toStringAsFixed(1)} MB'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: () => SharePlus.instance
                        .share(ShareParams(files: [XFile(f.path)])),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(f),
                  ),
                ],
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => ViewerScreen.file(f.path)),
              ),
            ),
          );
        },
      ),
    );
  }
}
