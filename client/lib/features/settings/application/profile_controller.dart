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

  /// Updates the display name via [PATCH /me] and invalidates the local cache.
  ///
  /// Sets state to [AsyncLoading] while the request is in flight, then
  /// re-fetches the profile from the server/cache.
  Future<void> saveDisplayName(String name) async {
    state = const AsyncLoading();
    try {
      await _repo.updateMe(displayName: name);
    } catch (err, st) {
      // updateMe already threw a typed Failure; surface it as AsyncError.
      state = AsyncError(err, st);
      return;
    }
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
