import 'package:flutter_test/flutter_test.dart';
import 'package:vid_baaz/ui/fb_browser_screen.dart';

void main() {
  group('FbBrowserScreen.isFacebookLoginUrl (issue #25)', () {
    test('flags the desktop login page', () {
      expect(
        FbBrowserScreen.isFacebookLoginUrl(
            'https://www.facebook.com/login.php?next=foo'),
        isTrue,
      );
    });

    test('flags the mobile login path', () {
      expect(
        FbBrowserScreen.isFacebookLoginUrl(
            'https://m.facebook.com/login/'),
        isTrue,
      );
    });

    test('flags checkpoint (verification wall, also login-gated)', () {
      expect(
        FbBrowserScreen.isFacebookLoginUrl(
            'https://www.facebook.com/checkpoint/?next=foo'),
        isTrue,
      );
    });

    test('does NOT flag real video pages', () {
      expect(
        FbBrowserScreen.isFacebookLoginUrl(
            'https://www.facebook.com/ijazullahkhan29/videos/28785058964482652/'),
        isFalse,
      );
      expect(
        FbBrowserScreen.isFacebookLoginUrl(
            'https://www.facebook.com/reel/2602442030183424'),
        isFalse,
      );
    });

    test('does NOT flag share links (they resolve, not login)', () {
      expect(
        FbBrowserScreen.isFacebookLoginUrl(
            'https://www.facebook.com/share/v/1Gtm2RSxKH/'),
        isFalse,
      );
    });

    test('does NOT flag non-Facebook hosts with login in the path', () {
      expect(
        FbBrowserScreen.isFacebookLoginUrl(
            'https://example.com/login.php'),
        isFalse,
      );
    });
  });
}
