import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/locale/locale_provider.dart';
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
  Future<CacheResult<MeResponse>> build() async {
    final result = await _repo.getMe();
    _adoptLocale(result);
    return result;
  }

  /// Pushes the profile's locale into [profileLocaleProvider], which is what
  /// makes `localeProvider` switch from the device locale to the user's own.
  ///
  /// It is a push rather than a `ref.watch` on the other side because this
  /// controller is `autoDispose` and holds PII: a locale provider that watched
  /// it would keep the profile alive app-wide and fire a `/me` request from
  /// every screen that renders a date.
  ///
  /// Deliberately after the `await`, never during the synchronous part of
  /// [build] — modifying another provider while this one is initialising is a
  /// Riverpod error. A [NetworkRequired] result carries no profile and so
  /// leaves the previous answer standing.
  ///
  /// The `ref.mounted` check is the session guard this side of the app has.
  /// It is NOT the generation check `OnboardingStatusController` carries: this
  /// provider is `autoDispose` and dies with the screen, so a response landing
  /// after sign-out finds a disposed ref rather than a live one belonging to
  /// somebody else. Without the check, that case raises
  /// `UnmountedRefException` from `ref.read`.
  ///
  /// **Scope, precisely: the check covers THIS method and nothing beyond it.**
  /// On the [build] path it is the whole story — the continuation runs on a
  /// disposed element, nothing listens, and the adopt is simply skipped. On the
  /// [saveDisplayName] path it is not: the very next statement is
  /// `state = refreshed`, and the `Notifier` state setter raises the same
  /// `UnmountedRefException` — which, unlike the one inside the disposed
  /// build, is NOT swallowed. It propagates to the awaiting caller and is
  /// absorbed by the blanket `catch (_)` in `profile_screen.dart`, where the
  /// user sees the generic "could not save your changes" snackbar for a save
  /// that in fact succeeded. That is pre-existing behaviour of the save path,
  /// not something this check introduces or fixes; it is written down here so
  /// nobody reads "the guard handles disposal" and believes the save path is
  /// covered too.
  void _adoptLocale(CacheResult<MeResponse> result) {
    final me = switch (result) {
      Fresh(:final value) => value,
      Stale(:final value) => value,
      NetworkRequired() => null,
    };
    if (me == null || !ref.mounted) return;
    ref.read(profileLocaleProvider.notifier).adopt(me.locale);
  }

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
      _adoptLocale(value!);
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
///
/// `autoDispose`: the profile holds decrypted, per-user PII, so its in-memory
/// state must NOT outlive the screen that shows it. When the user signs out the
/// ProfileScreen unmounts and this provider is disposed, so a subsequent login
/// (potentially a different account on a shared device) rebuilds and fetches
/// its own profile rather than reusing the previous session's data.
final profileControllerProvider =
    AsyncNotifierProvider.autoDispose<ProfileController, CacheResult<MeResponse>>(
  ProfileController.new,
);
