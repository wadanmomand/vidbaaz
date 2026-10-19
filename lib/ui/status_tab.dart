/// Status tab: permission gate -> grid of WhatsApp statuses -> save.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../status/status_models.dart';
import '../status/status_repository.dart';
import 'viewer_screen.dart';

class StatusTab extends StatefulWidget {
  const StatusTab({super.key});

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  final _repo = StatusRepository();
  bool? _hasAccess;
  bool _loading = false;
  List<StatusItem> _items = [];
  StatusApp? _filter;
  List<StatusApp> _apps = [];

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final ok = await _repo.hasAccess();
    if (!mounted) return;
    setState(() => _hasAccess = ok);
    if (ok) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _repo.loadStatuses();
      final apps = await _repo.availableApps();
      if (!mounted) return;
      setState(() {
        _items = items;
        _apps = apps;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _request() async {
    final ok = await _repo.requestAccess();
    if (!mounted) return;
    setState(() => _hasAccess = ok);
    if (ok) {
      _load();
    } else {
      _showManualSteps();
    }
  }

  void _showManualSteps() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Permission needed'),
        content: const Text(
          'Android 11 and above require "All files access" to read status folders.\n\n'
          '1. Tap OPEN SETTINGS below\n'
          '2. Turn ON "Allow access to all files"\n'
          '3. Come back and tap REFRESH',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _repo.openAllFilesAccessSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(StatusItem item) async {
    try {
      final path = await _repo.save(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to gallery: ${path.split('/').last}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasAccess == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasAccess == false) {
      return _permissionGate();
    }
    return _grid();
  }

  Widget _permissionGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_shared_outlined,
                size: 72, color: Colors.white38),
            const SizedBox(height: 16),
            const Text(
              'To show WhatsApp statuses, the app needs file access.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _request,
              icon: const Icon(Icons.lock_open),
              label: const Text('Grant Access'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid() {
    final items = _filter == null
        ? _items
        : _items.where((i) => i.app == _filter).toList();
    return Column(
      children: [
        if (_apps.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                const SizedBox(width: 8),
                for (final app in _apps)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(app.label),
                      selected: _filter == app,
                      onSelected: (_) => setState(() => _filter = app),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? _empty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _tile(items[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _empty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No statuses found.\nView some statuses in WhatsApp first, then pull down to refresh.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, height: 1.6),
        ),
      ),
    );
  }

  Widget _tile(StatusItem item) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ViewerScreen.file(item.path, onSave: () => _save(item)),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item.isVideo
                ? Container(
                    color: Colors.black54,
                    child: const Icon(Icons.play_circle_fill,
                        size: 40, color: Colors.white70),
                  )
                : Image.file(File(item.path), fit: BoxFit.cover),
          ),
          if (item.isVideo)
            const Positioned(
              right: 4,
              bottom: 4,
              child: Icon(Icons.videocam, size: 18, color: Colors.white),
            ),
          Positioned(
            right: 4,
            top: 4,
            child: GestureDetector(
              onTap: () => _save(item),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.download, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
