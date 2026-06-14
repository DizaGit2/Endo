import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/features/settings/data/me_repository.dart';

// ---------------------------------------------------------------------------
// ProfileController
// ---------------------------------------------------------------------------

/// Drives the Profile screen.
///
/// State:
/// - [AsyncLoading]  — initial load in progress.
/// - [AsyncData<CacheResult<MeResponse>>]  — loaded:
///     • [Fresh]           — live data from server.
///     • [Stale]           — offline; data from cache (shows a stale badge).
///     • [NetworkRequired] — no network AND no cache; show network-required UI.
/// - [AsyncError]    — real error (auth/validation/unexpected); show error UI.
///
/// Note: [NetworkRequired] is exposed as [AsyncData] (not [AsyncError]) because
/// it is an expected offline state, not an exceptional failure — the UI should
/// display a "connect to load profile" message rather than a generic error.
class ProfileController
    extends AsyncNotifier<CacheResult<MeResponse>> {
  MeRepository get _repo => ref.read(meRepositoryProvider);

  @override
  Future<CacheResult<MeResponse>> build() => _repo.getMe();

  // ── saveDisplayName ────────────────────────────────────────────────────────

  /// Updates the display name via [PATCH /me] and invalidates the local cache,
  /// then re-fetches the profile.
  ///
  /// The currently-displayed profile stays on screen during the save; a failure
  /// is RETHROWN to the caller (the edit dialog surfaces it inline) rather than
  /// replacing the whole screen with an error and losing the loaded data.
  Future<void> saveDisplayName(String name) async {
    await _repo.updateMe(displayName: name); // throws a typed Failure on error
    // Refresh: re-fetch profile (may return Fresh or Stale depending on
    // network state after the write).
    state = await AsyncValue.guard(_repo.getMe);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [ProfileController] as an [AsyncNotifier].
final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, CacheResult<MeResponse>>(
  ProfileController.new,
);
