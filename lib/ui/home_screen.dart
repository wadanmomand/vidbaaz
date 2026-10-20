/// Home shell: bottom navigation across Home / Status / Download / Saved.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'disclaimer.dart';
import 'downloader_tab.dart';
import 'home_tab.dart';
import 'saved_tab.dart';
import 'status_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final _savedKey = GlobalKey<SavedTabState>();

  void _goTo(int i) {
    setState(() => _index = i);
    // The Saved tab keeps its state in the IndexedStack; refresh its file
    // list every time it becomes visible so newly saved items appear.
    if (i == 3) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _savedKey.currentState?.refresh());
    }
  }

  @override
  void initState() {
    super.initState();
    _maybeShowDisclaimer();
  }

  Future<void> _maybeShowDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('disclaimer_seen') == true) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DisclaimerDialog(),
    );
    await prefs.setBool('disclaimer_seen', true);
  }

  @override
  Widget build(BuildContext context) {
    final onHome = _index == 0;
    return Scaffold(
      // The finalized home concept is full-bleed art; no app bar or
      // Flutter nav on top of it — its baked buttons/nav have tap zones.
      appBar: onHome
          ? null
          : AppBar(
              title: const Text(
                'VIDBAAZ',
                style: TextStyle(
                    fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
      body: IndexedStack(
        index: _index,
        children: [
          HomeTab(onNavigate: _goTo),
          const StatusTab(),
          const DownloaderTab(),
          SavedTab(key: _savedKey),
        ],
      ),
      bottomNavigationBar: onHome
          ? null
          : BottomNavigationBar(
              currentIndex: _index,
              onTap: _goTo,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.photo_library_outlined),
                  activeIcon: Icon(Icons.photo_library),
                  label: 'Status',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.cloud_download_outlined),
                  activeIcon: Icon(Icons.cloud_download),
                  label: 'Download',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.folder_outlined),
                  activeIcon: Icon(Icons.folder),
                  label: 'Saved',
                ),
              ],
            ),
    );
  }
}
