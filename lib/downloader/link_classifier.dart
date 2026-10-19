/// Classifies a pasted link into a download strategy.
///
/// MVP reality (client-side only, no backend):
/// - direct media file URLs (.mp4 etc.) -> download immediately
/// - Facebook public video pages -> resolve via page HTML parse
/// - YouTube -> unsupported (Play policy)
/// - Instagram/TikTok login-walled content -> unsupported for now
library;

enum LinkKind { directMedia, facebook, tiktok, unsupported }

class ClassifiedLink {
  final LinkKind kind;
  final String url;
  final String reason;

  const ClassifiedLink(this.kind, this.url, [this.reason = '']);
}

class LinkClassifier {
  static const _mediaExts = {'.mp4', '.webm', '.mov', '.3gp', '.m4v'};

  ClassifiedLink classify(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      return const ClassifiedLink(
          LinkKind.unsupported, '', 'Please paste a video link first.');
    }
    var normalized = input;
    if (!normalized.contains('://')) normalized = 'https://$normalized';
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return ClassifiedLink(
          LinkKind.unsupported, input, 'That does not look like a valid link.');
    }
    final host = uri.host.toLowerCase();
    if (!host.contains('.')) {
      return ClassifiedLink(
          LinkKind.unsupported, input, 'That does not look like a valid link.');
    }
    final path = uri.path.toLowerCase();

    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      return ClassifiedLink(LinkKind.unsupported, normalized,
          'YouTube downloads are not allowed by Play Store policy.');
    }
    if (host.contains('instagram.com') ||
        host.contains('twitter.com') ||
        host.contains('x.com')) {
      return ClassifiedLink(LinkKind.unsupported, normalized,
          'This site needs login access — coming in a later update.');
    }
    if (host.contains('tiktok.com')) {
      return ClassifiedLink(LinkKind.tiktok, normalized);
    }
    if (host.contains('facebook.com') || host.contains('fb.watch')) {
      return ClassifiedLink(LinkKind.facebook, normalized);
    }
    if (_mediaExts.any(path.endsWith)) {
      return ClassifiedLink(LinkKind.directMedia, normalized);
    }
    // Unknown page: try it as a possible direct media link anyway —
    // the downloader verifies the content-type before saving.
    return ClassifiedLink(LinkKind.directMedia, normalized);
  }
}
