/// Models for WhatsApp-style status media items.
library;

enum StatusApp { whatsapp, whatsappBusiness, gbWhatsapp }

extension StatusAppLabel on StatusApp {
  String get label => switch (this) {
        StatusApp.whatsapp => 'WhatsApp',
        StatusApp.whatsappBusiness => 'WhatsApp Business',
        StatusApp.gbWhatsapp => 'GBWhatsApp',
      };
}

class StatusItem {
  final String path;
  final StatusApp app;
  final bool isVideo;
  final int sizeBytes;
  final DateTime modified;

  const StatusItem({
    required this.path,
    required this.app,
    required this.isVideo,
    required this.sizeBytes,
    required this.modified,
  });

  String get fileName => path.split(RegExp(r'[/\\]')).last;
}
