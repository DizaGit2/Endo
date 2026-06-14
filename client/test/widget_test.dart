import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

void main() {
  testWidgets('LumenApp smoke test — "Lumen" text renders', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LumenApp()));

    // The placeholder home shows a centred "Lumen" text.
    expect(find.text('Lumen'), findsOneWidget);
  });

  testWidgets(
    'LumenApp smoke test — light theme carries LumenColors extension',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: LumenApp()));

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final ext = app.theme!.extension<LumenColors>();

      expect(ext, isNotNull);
      // Spot-check: the extension's accent matches the light-mode token.
      expect(ext!.accent, lumenLight.accent);
      expect(ext.bg, lumenLight.bg);
    },
  );
}
