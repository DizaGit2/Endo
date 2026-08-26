// ---------------------------------------------------------------------------
// retry_policy.dart — the app-wide answer to "should riverpod rebuild this
// provider after its build failed?" (P4b-T26)
// ---------------------------------------------------------------------------

/// Lumen's riverpod `Retry` policy: **a failed provider build is never re-run
/// automatically.**
///
/// ## What it replaces
///
/// riverpod 3.3.2's `ProviderContainer.defaultRetry` stops retrying only for
/// `error is ProviderException || error is Error`. Every member of this app's
/// sealed `Failure` hierarchy (`core/error/failure.dart`) is neither, so under
/// the default a failed read is rebuilt **ten times with 200 ms → 6.4 s
/// exponential backoff — about 38 seconds** — and for all of it
/// `ProviderElement.triggerRetry` publishes
/// `AsyncLoading(error: …, retrying: true)`. That state answers `isLoading`,
/// and `AsyncValue.when` tests `isLoading` before `hasError`, so every screen
/// built on `when` renders its **spinner** for most of a minute instead of the
/// error/retry body designed for it.
///
/// ## Why NOTHING is retryable, including the "transient" shapes
///
/// The tempting middle course is to keep retrying the two failures this
/// codebase already calls ambiguous — `NetworkFailure` and `ServerFailure`, the
/// pair `cachedWrite`'s `_invalidateOnAmbiguousFailure` and `cachedRead`'s
/// `_resolveFailure` both branch on (`core/cache/cached_query.dart`). **That
/// distinction is deliberately NOT reused here, and the reason is that the
/// layer below has already applied it.**
///
///  * On a READ that pair is already classified one layer down, and this is
///    the load-bearing half: `_resolveFailure` catches exactly `NetworkFailure`
///    and `ServerFailure` and answers `Stale(cached)` when there is a cached
///    value and `NetworkRequired(...)` when there is not — both *values*, not
///    throws. Retrying here would re-litigate that decision silently, behind a
///    spinner.
///
///    **What it does NOT mean is that those two never reach a provider build
///    as a throw — they do, and an earlier draft of this file said otherwise.**
///    The cache-less half comes back out as one: `NetworkRequired(:final
///    failure) => throw failure` in `CycleCalendarController.build`,
///    `DayDetailController.build` (twice) and `CycleSettingsController.build`.
///    With no cached value there is nothing to render, so those screens
///    deliberately ask for their error/retry body rather than an empty one —
///    which is an ERROR state, not the "designed offline state" the sentence
///    above used to claim.
///
///    So name the trade this policy actually makes: on screens 10, 11 and 32 an
///    uncached read that fails transiently and would have succeeded on attempt
///    2 used to heal itself within ~38 s with no user action, and now surfaces
///    the error body and waits for a tap. That is the intended exchange — the
///    user could not tell that recovery from a hang, and the identical silent
///    ten-attempt loop was being spent on a `ServerFailure` from a malformed
///    2xx body — but it is behaviour REMOVED, not behaviour that was never
///    there.
///  * So the full set that arrives as a thrown `Failure` is the one
///    `_resolveFailure` classifies as real — auth, validation, not-found,
///    conflict, rate-limit, TLS, unknown — plus the three re-throws above.
///    Not one of those improves by being repeated: a
///    `RateLimitFailure` retried ten times makes the rate limit worse, an
///    `AuthFailure` has already been through `AuthInterceptor`'s refresh, and
///    `TlsFailure`'s own dartdoc says in capitals that it must NEVER be
///    treated as a transient offline state.
///  * The retry the user needs already exists and is visible: every failure
///    surface in this app carries `LumenErrorRetry`/`LumenRetryButton`, and
///    `test/support/retry_trap.dart` pins that a tap re-issues exactly one
///    request. A silent framework retry does not add a recovery path — it
///    hides the one that is already there, and wins the race for 38 seconds.
///
/// So the policy is unconditional, and it is unconditional the same way the
/// four providers that had already discovered this problem one at a time chose
/// to be — `sessionTodayProvider`, `cycleCalendarControllerProvider`,
/// `dayDetailControllerProvider` and `dashboardControllerProvider` each pass
/// this same "never" rather than a shape test. This function generalises a
/// decision the codebase had already made four times; it does not invent one.
///
/// ## Where it is applied
///
/// At the container, which is the only place that reaches every provider:
/// `LumenRootScope` (`app.dart`) in production, and `pump_app.dart` /
/// `golden_app.dart` in tests, so a widget test observes what a user observes.
/// **Every bare `ProviderContainer` a test builds names it too** — all ~40 of
/// them, and `pump_app.dart` REJECTS a caller-supplied container that does
/// not. That uniformity is fix round 1: applying the policy on only one of
/// `_pumpScoped`'s two branches had left `container:` as a way back to
/// `defaultRetry` straight through the harness meant to prevent it, and
/// `provider_retry_policy_test.dart`'s source audit now walks BOTH
/// constructors so the next site cannot omit it. The four providers above
/// additionally name it at their own declaration, which is what covers the
/// controller tests' containers from the other side. Note that a provider's own
/// `retry` WINS over its container's — `ProviderElement.triggerRetry`
/// (`element.dart`) resolves `origin.retry ?? container.retry ??
/// ProviderContainer.defaultRetry` — so those four are governed by this symbol
/// rather than by whichever scope mounts them. Both spellings name the same
/// function today, so there is no divergence; a future per-scope override would
/// not reach those four, and that is the thing to remember before writing one.
///
/// Returning `null` means "do not retry"; the signature is riverpod's `Retry`
/// (`provider_container.dart`, the `Retry` typedef — not exported by
/// `flutter_riverpod`, hence no [] link), so both parameters are ignored on
/// purpose rather than absent.
Duration? lumenRetry(int retryCount, Object error) => null;
