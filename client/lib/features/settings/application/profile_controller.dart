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
  /// of the PATCH itself is RETHROWN to the caller (the edit dialog surfaces it
  /// inline) rather than replacing the whole screen with an error.
  ///
  /// The PATCH invalidates the `GET:/me` cache entry, so the immediate re-fetch
  /// has no cached fallback. If that re-fetch then fails transiently (returns
  /// [NetworkRequired] or throws) we must NOT blank the screen — the save
  /// already succeeded. In that case we keep the profile on screen with the
  /// just-saved name; the next natural read reconciles with the server.
  Future<void> saveDisplayName(String name) async {
    final previous = state.value;
    await _repo.updateMe(displayName: name); // throws a typed Failure on error
    final refreshed = await AsyncValue.guard(_repo.getMe);

    // Adopt the re-fetch only if it produced usable profile data.
    final value = refreshed.value;
    if (value is Fresh<MeResponse> || value is Stale<MeResponse>) {
      state = refreshed;
      return;
    }

    // Re-fetch failed (AsyncError) or returned NetworkRequired after a
    // SUCCESSFUL save: retain the on-screen profile with the new name.
    if (previous != null) {
      state = AsyncData(_withDisplayName(previous, name));
    } else {
      state = refreshed;
    }
  }

  /// Returns [result] with the display name replaced by [name], preserving the
  /// [Fresh]/[Stale] variant. [NetworkRequired] has no value to update.
  CacheResult<MeResponse> _withDisplayName(
    CacheResult<MeResponse> result,
    String name,
  ) {
    MeResponse withName(MeResponse me) =>
        me.rebuild((b) => b..displayName = name);
    return switch (result) {
      Fresh(:final value) => Fresh(withName(value)),
      Stale(:final value) => Stale(withName(value)),
      NetworkRequired() => result,
    };
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
