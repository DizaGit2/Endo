import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

import '../support/harness.dart';

/// The bar with a different tab selected in each copy.
///
/// `LumenBottomNav` is the second widget declared in `lumen_scaffold.dart`, and
/// it owns this golden because the registry's unit is the widget, not the file:
/// `lumen_scaffold`'s golden photographs the bar too, but only ever on Home, so
/// it would keep passing if selection stopped moving. Three positions in one
/// image is what makes the accent/muted split and the accent-soft indicator
/// falsifiable.
Widget _bars(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  return ColoredBox(
    color: c.bg,
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        LumenBottomNav(currentIndex: 0),
        SizedBox(height: 32),
        LumenBottomNav(currentIndex: 2),
        SizedBox(height: 32),
        LumenBottomNav(currentIndex: 4),
      ],
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenBottomNav',
    fileName: 'lumen_bottom_nav',
    build: (brightness) =>
        goldenApp(home: _bars(brightness), brightness: brightness),
  );
}
