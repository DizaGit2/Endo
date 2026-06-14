import 'dart:async';

import 'package:alchemist/alchemist.dart';

/// Global Alchemist configuration applied to every test under test/.
///
/// Strategy for cross-platform determinism:
/// - CI goldens (obscureText: true, renderShadows: false) are always generated
///   and compared. Text is replaced by solid colour blocks so the output is
///   identical regardless of the host OS or font renderer.
/// - Platform goldens are disabled entirely: we never want host-specific images
///   committed as source-of-truth, which would cause CI failures whenever the
///   developer's OS differs from the CI runner.
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
