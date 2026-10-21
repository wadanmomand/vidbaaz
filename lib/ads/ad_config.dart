/// AdMob configuration (VidBaaz — Google TEST IDs until production IDs land).
///
/// PRODUCTION STATE: Google's official TEST IDs are used everywhere, so
/// only test ads are served. The production AdMob account was rejected
/// (2026-10-14); when it is approved, replace the four values below with
/// the real App ID + banner unit ID (and the App ID in
/// AndroidManifest.xml / Info.plist), or pass them at build time:
///
///   flutter build appbundle \
///     --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-XXXX/XXXX \
///     --dart-define=ADMOB_BANNER_IOS=ca-app-pub-XXXX/XXXX
library;

import 'dart:io';

class AdConfig {
  /// Google TEST banner unit — Android.
  static const String _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';

  /// Google TEST banner unit — iOS.
  static const String _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';

  /// Banner ad unit for the current platform.
  static String get bannerUnitId {
    if (Platform.isIOS) {
      return const String.fromEnvironment(
        'ADMOB_BANNER_IOS',
        defaultValue: _testBannerIos,
      );
    }
    return const String.fromEnvironment(
      'ADMOB_BANNER_ANDROID',
      defaultValue: _testBannerAndroid,
    );
  }
}
