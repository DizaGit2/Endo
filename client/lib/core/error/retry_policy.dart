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
///  * A `NetworkFailure`/`ServerFailure` on a READ never reaches a provider
///    build as a throw. `_resolveFailure` catches exactly those two and answers
///    `Stale(cached)` when there is a cached value and `NetworkRequired(...)`
///    when there is not — both of which are *values*, and both of which the
///    screens render as designed offline states. Retrying them here would
///    re-litigate, silently and behind a spinner, a decision `cachedRead`
///    already made explicitly.
///  * What DOES arrive as a thrown `Failure` is therefore the set
///    `_resolveFailure` classifies as real: auth, validation, not-found,
///    conflict, rate-limit, TLS, unknown — plus a controller's own deliberate
///    `throw failure` on a `NetworkRequired`, which is the screen *asking* for
///    its error state. Not one of those improves by being repeated: a
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
/// The four providers above additionally name it at their own declaration —
/// belt-and-braces for the controller tests that build a bare
/// `ProviderContainer` of their own, where no root scope exists to inherit
/// from.
///
/// Returning `null` means "do not retry"; the signature is riverpod's `Retry`
/// (`provider_container.dart`, the `Retry` typedef — not exported by
/// `flutter_riverpod`, hence no [] link), so both parameters are ignored on
/// purpose rather than absent.
Duration? lumenRetry(int retryCount, Object error) => null;
