// Golden tests for ProfileScreen — light + dark at 390x844.
//
// A fake ProfileController holds a pre-loaded Fresh(MeResponse) so the image is
// deterministic and settles (never golden a loading state).

import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';

import '../../support/harness.dart';

/// A fake [ProfileController] that immediately yields a loaded profile.
class _FreshProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async =>
      Fresh(meResponseFixture(id: 'user-golden'));

  @override
  Future<void> saveDisplayName(String name) async {}
}

void main() {
  goldenTestLightAndDark(
    subject: 'ProfileScreen',
    fileName: 'profile_screen',
    build: (brightness) => goldenApp(
      home: const ProfileScreen(),
      brightness: brightness,
      overrides: [
        ...lumenOverrides(),
        profileControllerProvider.overrideWith(_FreshProfileController.new),
      ],
    ),
  );
}
