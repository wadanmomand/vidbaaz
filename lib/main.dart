import 'package:flutter/material.dart';

import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const VidBaazApp());
}

class VidBaazApp extends StatelessWidget {
  const VidBaazApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VidBaaz: Video Downloader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}
