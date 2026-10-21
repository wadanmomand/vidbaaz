/// Persistent AdMob banner shown above the bottom navigation bar
/// (on the Status / Download / Saved tabs; never over the full-bleed
/// home art).
///
/// Renders nothing until an ad has loaded, and renders nothing at all if
/// loading fails (offline, no fill, plugin unavailable) — the calculator
/// itself always works fully offline.
library;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      final ad = BannerAd(
        adUnitId: AdConfig.bannerUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            if (mounted) {
              setState(() {
                _ad = null;
                _loaded = false;
              });
            }
          },
        ),
      );
      _ad = ad;
      ad.load();
    } catch (_) {
      // Ads must never break the app (e.g. plugin missing in tests).
      _ad = null;
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Center(
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}
