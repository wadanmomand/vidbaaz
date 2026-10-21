import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ads are best-effort only: a failure here must never block the app.
  try {
    await MobileAds.instance.initialize();
  } catch (_) {
    // Ignore — the banner simply stays hidden.
  }
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
