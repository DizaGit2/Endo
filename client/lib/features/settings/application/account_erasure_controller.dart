import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/settings/data/me_repository.dart';

// ---------------------------------------------------------------------------
// AccountErasureController
// ---------------------------------------------------------------------------

/// Drives screen 36's one write: `DELETE /me` (P4b-T22c).
///
/// The state is a single flag — **is a request in flight** — and that is the
/// whole model, because this surface has no form and nothing to re-render on
/// success: an accepted request ends the session, and a refused one leaves the
/// screen exactly as it was. The outcome is RETURNED to the caller rather than
/// stored, the shape `PeriodEditorController.delete()` already uses, so the
/// screen decides what to say about it.
///
/// **What this controller deliberately does NOT do is end the session.** The
/// sign-out is the screen's, immediately after the message it shows — see
/// `privacy_screen.dart`. Putting it here would make the message a race
/// against the redirect that the sign-out triggers.
class AccountErasureController extends Notifier<bool> {
  /// No request is in flight when the screen opens.
  @override
  bool build() => false;

  /// Asks the server to erase this account, and reports whether the request
  /// was **accepted**.
  ///
  /// `true` means the server answered `202` — the erasure was ENQUEUED. It
  /// does **not** mean the erasure has run, and no caller may render it as if
  /// it had. `false` means the request was refused or never arrived: the
  /// account is unchanged as far as this client can tell, and the session must
  /// be left alone.
  ///
  /// Every failure is folded into that one `false`. There is nothing per-field
  /// to surface — the request has no body, so it has no field a 400 could name
  /// — and the three refusals that can actually happen (no connectivity, 401,
  /// 5xx) all leave the user in the same place with the same next step. The
  /// typed [Failure] is swallowed rather than rethrown so the screen has one
  /// outcome to render instead of two.
  Future<bool> requestErasure() async {
    state = true;

    Failure? rejected;
    try {
      await ref.read(meRepositoryProvider).deleteMe();
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      rejected = const UnknownFailure();
    }

    // `ref.mounted` before touching state: the provider can be disposed while
    // the request is out (the container goes away with the app, or a test's
    // scope ends), and a Notifier's state setter throws after that.
    if (ref.mounted) state = false;

    return rejected == null;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Whether an erasure request is currently in flight.
///
/// Not `autoDispose`: the flag has to outlive a rebuild of the row that reads
/// it, and there is exactly one of these per app.
final accountErasureControllerProvider =
    NotifierProvider<AccountErasureController, bool>(
      AccountErasureController.new,
    );
