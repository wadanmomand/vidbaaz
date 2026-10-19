/// Home tab: the FINAL approved home concept art, shown fully (no crop),
/// with invisible tap zones over its baked-in buttons and nav
/// (same pattern as Pawzzle Smash home: concept art as bg + tap zones).
library;

import 'package:flutter/material.dart';

class HomeTab extends StatefulWidget {
  final void Function(int tab) onNavigate;

  const HomeTab({super.key, required this.onNavigate});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _artSize; // intrinsic size of home-final.png

  static const _artAspect = 1152 / 2048;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = const AssetImage('assets/home-final.png');
    _stream = provider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _artSize = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            ));
      }
    });
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // Fit the whole art inside the screen (contain) so nothing is
        // cropped on tall phones; letterbox bands blend into the navy bg.
        final aspect = _artSize == null
            ? _artAspect
            : _artSize!.width / _artSize!.height;
        var iw = w;
        var ih = w / aspect;
        if (ih > h) {
          ih = h;
          iw = h * aspect;
        }

        Widget zone(Key key, double l, double t, double r, double b, int tab) {
          return Positioned(
            left: l * iw,
            top: t * ih,
            right: (1 - r) * iw,
            bottom: (1 - b) * ih,
            child: GestureDetector(
              key: key,
              behavior: HitTestBehavior.translucent,
              onTap: () => widget.onNavigate(tab),
              child: const SizedBox.expand(),
            ),
          );
        }

        return Container(
          color: const Color(0xFF0D1330),
          alignment: Alignment.center,
          child: SizedBox(
            width: iw,
            height: ih,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/home-final.png',
                  fit: BoxFit.fill,
                  key: const Key('homeArt'),
                ),
                // Baked golden "Save Status" button.
                zone(const Key('zoneSaveStatus'), 0.035, 0.723, 0.473, 0.811, 1),
                // Baked teal "Download Video" button.
                zone(const Key('zoneDownloadVideo'), 0.512, 0.723, 0.951, 0.811, 2),
                // Baked bottom nav.
                zone(const Key('zoneNavStatus'), 0.113, 0.889, 0.286, 0.972, 1),
                zone(const Key('zoneNavDownload'), 0.417, 0.889, 0.599, 0.972, 2),
                zone(const Key('zoneNavSaved'), 0.720, 0.889, 0.894, 0.972, 3),
              ],
            ),
          ),
        );
      },
    );
  }
}
