import 'package:flutter/material.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

import '../support/harness.dart';

/// The scaffold's own golden — chrome, padding and bottom nav, with enough
/// body content to show the card treatment.
Widget _scaffold() {
  return LumenScaffold(
    appBar: AppBar(title: const Text('Lumen')),
    bottomNavigationBar: const LumenBottomNav(currentIndex: 0),
    padding: const EdgeInsets.all(16),
    body: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Today',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                ),
                SizedBox(height: 4),
                Text('Cycle day 14 · Ovulatory phase'),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenScaffold',
    fileName: 'lumen_scaffold',
    build: (brightness) => goldenApp(home: _scaffold(), brightness: brightness),
  );
}
