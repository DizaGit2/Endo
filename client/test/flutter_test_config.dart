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
/// the host OS or font renderer"*. It is not, and believing it is what let
/// four screens diverge silently until the branch was first pushed. Blocking
/// makes the image insensitive to which GLYPHS are drawn; it does not make it
/// insensitive to WHERE the blocks land. Some placements in this app are
/// sub-pixel and host-dependent — see `support/golden_app.dart` rule 9 for
/// the measured mechanism, the predictive rule, and the consequence that
/// follows from it: **the committed masters are Linux renders and
/// `goldenTestLightAndDark` compares them on Linux only.** `diffThreshold`
/// stays at Alchemist's default 0.0 (P4b-T21b R14): a tolerance wide enough to
/// absorb the 614 px seen here would also absorb a real regression.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  return AlchemistConfig.runWithConfig(
    config: const AlchemistConfig(
      // Disable human-readable platform goldens so OS font differences
      // (macOS vs Linux vs Windows) never cause spurious failures.
      platformGoldensConfig: PlatformGoldensConfig(enabled: false),
      // CI goldens: obscure text + no shadows → identical pixels everywhere.
      ciGoldensConfig: CiGoldensConfig(
        enabled: true,
        obscureText: true,
        renderShadows: false,
      ),
    ),
    run: testMain,
  );
}
