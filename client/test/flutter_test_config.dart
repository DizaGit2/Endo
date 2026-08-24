import 'dart:async';

import 'package:alchemist/alchemist.dart';

/// Global Alchemist configuration applied to every test under test/.
///
/// Strategy for cross-platform determinism:
/// - CI goldens use `obscureText: true`, `renderShadows: false`, so the images
///   record layout, geometry and non-text colour rather than glyphs.
/// - Platform goldens are disabled entirely: we never want host-specific images
///   committed as source-of-truth, which would cause CI failures whenever the
///   developer's OS differs from the CI runner.
///
/// **What this file used to claim, and why it was wrong (P4b-T25a).** The
/// sentence here said blocking text made the output *"identical regardless of
/// the host OS or font renderer"*. It does not. Blocking makes the image
/// insensitive to which GLYPHS are drawn; it does not make it insensitive to
/// WHERE the blocks land, and believing otherwise is what let four screens
/// diverge silently until this branch was first pushed. Placement is
/// host-independent only while it comes out of integer or exact-half
/// arithmetic — which, since T25a's fix-round-1, it does everywhere in this
/// app. See `support/golden_app.dart` rule 9 for the measurement, the one
/// production construct that broke it (`hint: ''`), and the assert that now
/// prevents it.
///
/// `diffThreshold` stays at Alchemist's default 0.0 (P4b-T21b R14): a tolerance
/// wide enough to absorb the 614 px seen on that push would also absorb a real
/// regression. The cause was removed instead.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  return AlchemistConfig.runWithConfig(
    config: const AlchemistConfig(
      // Disable human-readable platform goldens so OS font differences
      // (macOS vs Linux vs Windows) never cause spurious failures.
      platformGoldensConfig: PlatformGoldensConfig(enabled: false),
      // CI goldens: text is blocked out and shadows are off, so the images
      // record geometry rather than glyphs. NOT "identical pixels everywhere"
      // — see the doc above and golden_app.dart rule 9.
      ciGoldensConfig: CiGoldensConfig(
        enabled: true,
        obscureText: true,
        renderShadows: false,
      ),
    ),
    run: testMain,
  );
}
