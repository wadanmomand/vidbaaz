/// First-launch fair-use disclaimer.
library;

import 'package:flutter/material.dart';

class DisclaimerDialog extends StatelessWidget {
  const DisclaimerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Before you start'),
      content: const Text(
        'VidBaaz: Video Downloader saves WhatsApp statuses you have already '
        'viewed, and downloads videos from links you paste.\n\n'
        'Only download content you own or have permission to save. '
        'Respect creators and platform terms. '
        'This app is not affiliated with WhatsApp, Meta, or any social platform.',
        style: TextStyle(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('I Understand'),
        ),
      ],
    );
  }
}
