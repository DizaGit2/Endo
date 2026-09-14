import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

import 'support/harness.dart';

void main() {
  testWidgets(
    'LumenApp smoke test — welcome screen renders when unauthenticated',
    (tester) async {
      await pumpLumenApp(
        tester,
        overrides: lumenOverrides(auth: AuthStatus.unauthenticated),
      );

      // The welcome screen shows the app tagline headline.
      expect(find.text('Your cycle, understood'), findsOneWidget);
    },
  );

  testWidgets(
    'LumenApp smoke test — light theme carries LumenColors extension',
    (tester) async {
      await pumpLumenApp(
        tester,
        overrides: lumenOverrides(auth: AuthStatus.unauthenticated),
      );

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final ext = app.theme!.extension<LumenColors>();

      expect(ext, isNotNull);
      // Spot-check: the extension's accent matches the light-mode token.
      expect(ext!.accent, lumenLight.accent);
      expect(ext.bg, lumenLight.bg);
    },
  );
}
