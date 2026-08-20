import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/checkin/application/quick_checkin_controller.dart';
import 'package:lumen/features/checkin/presentation/quick_checkin_screen.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';

import '../../support/harness.dart';

/// A [QuickCheckinController] pinned to a fixed [QuickCheckinForm] — a golden
/// has no `WidgetTester` to drive taps with, so a "populated" scenario is
/// reached by overriding the provider rather than by tapping through it.
class _FixedQuickCheckinController extends QuickCheckinController {
  _FixedQuickCheckinController(this._form);
  final QuickCheckinForm _form;

  @override
  QuickCheckinForm build() => _form;
}

/// Screen 9 over its own bottom-sheet chrome, at whichever [form] the caller
/// wants pinned. A fresh, scoped [ProviderScope] per call — never the outer
/// [goldenApp] frame's own overrides — so the OPENING and POPULATED
/// scenarios below can share one golden file's `_states` column without one
/// state's override leaking into the other's.
Widget _sheet(Brightness brightness, QuickCheckinForm form) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  return ProviderScope(
    overrides: [
      quickCheckinControllerProvider.overrideWith(
        () => _FixedQuickCheckinController(form),
      ),
    ],
    child: Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: c.bg),
        const Align(
          alignment: Alignment.bottomCenter,
          child: LumenBottomSheet(child: QuickCheckinScreen()),
        ),
      ],
    ),
  );
}

void main() {
  // ---------------------------------------------------------------------
  // Opening state — the anti-fabrication mechanical control (brief's F11:
  // CI goldens block out TEXT but record NON-TEXT paint, so a filled first
  // stop from a stray `?? 0` default shows up here as an accent fill even
  // though the numeral itself is blocked). Both controls null/unselected —
  // this is the canonical `quick_checkin_screen_{light,dark}.png` pair the
  // screen registry looks for, and the brief's own instruction: "if you
  // ship only one, ship the opening state."
  // ---------------------------------------------------------------------

  goldenTestLightAndDark(
    subject: 'QuickCheckinScreen',
    fileName: 'quick_checkin_screen',
    build: (brightness) => goldenApp(
      home: _sheet(brightness, const QuickCheckinForm()),
      brightness: brightness,
    ),
  );

  // ---------------------------------------------------------------------
  // Populated state — a chosen pain stop and a chosen mood tile, so the
  // SELECTED-state paint (accent fill on the stop, accent-soft fill on the
  // mood tile) is pinned too, not just the empty case.
  // ---------------------------------------------------------------------

  goldenTestLightAndDark(
    subject: 'QuickCheckinScreen',
    fileName: 'quick_checkin_screen_populated',
    build: (brightness) => goldenApp(
      home: _sheet(
        brightness,
        const QuickCheckinForm(
          pain: 3,
          mood: 3,
          touchedPain: true,
          touchedMood: true,
        ),
      ),
      brightness: brightness,
    ),
  );
}
