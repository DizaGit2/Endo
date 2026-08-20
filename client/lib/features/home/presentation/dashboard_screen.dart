// Screen 8 — the dashboard (P4b-T17, READ SURFACE ONLY).
//
// The Home tab's landing screen, and — as of R-19 (`app_router.dart`) — the
// authenticated default: a signed-in, onboarded user lands here, not on
// screen 31 anymore. Reads `GET /me` (the greeting's name) and
// `CycleRepository.getCalendarMonth` for the CURRENT and PREVIOUS month
// (unconditionally — `dashboard_controller.dart`'s own dartdoc has the full
// "why unconditional" reasoning) and renders what P4a genuinely supplies.
// Writes nothing.
//
// Cuts from the mockup, and why (T17 brief §"What is CUT" has the full
// citations):
//  * the WHOLE hero card's contents — "Luteal phase" / "Day 22" / "of 28" /
//    the 62% confidence ring / "Add labs to sharpen prediction". None of
//    these has a data source in P4a (the phase engine is P6, C-09 is P6, labs
//    are P7a), and "of 28" was the only reason this screen would have read
//    `GET /settings/cycle` at all — that read is dropped entirely, not just
//    the number it would have answered. Unlike screen 11 (cut because screen
//    10 carries the phase-unavailable block one tap away), screen 8 IS a
//    top-level landing surface with a phase-shaped hole in the middle of it,
//    so it renders [LumenPhaseUnavailable] rather than nothing —
//    `ARCHITECTURE.md` §C.0.3: *render the unavailable state; do not infer
//    one.*
//  * the insight card — `user_insight_snapshot` has zero rows, no read
//    endpoint, and is structurally unreachable from the API (a NetArchTest
//    fact).
//  * the Energy card — `cycle_day_logs.energy` is a reserved column with no
//    writer and no CHECK in P4a (D-10). Card 2 becomes Mood instead — mood IS
//    on the same row, and this is the same "Pain & mood" pairing T16
//    established on screen 11.
//  * the month link — the Cycle tab already reaches the calendar, and a
//    second entry point with different back behaviour is precisely the
//    problem R-19 exists to fix.
//  * the WHOLE "Quick log" row (ruling R-20): at T17, Symptom (screen
//    12/T20) and Mood (screen 9/T18) have no destination yet, and Activity
//    is P5 — a "quick log" row containing only "More" is not a quick-log
//    row. T18 adds the Mood tile with screen 9; T20 adds the Symptom tile
//    with screen 12. Activity never ships in P4b. This screen therefore
//    lands with no actions on it beyond the bottom nav — the honest
//    consequence of building screens in dependency order.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/core/time/greeting_clock.dart'
    show greetingTimeOfDayProvider;
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';
import 'package:lumen/shared/widgets/lumen_retry_button.dart';

// ---------------------------------------------------------------------------
// The mood scale label
// ---------------------------------------------------------------------------

/// `cycle_day_logs.mood`'s 4-member scale, `Codes[value - 1]` — the wire
/// carries the integer 1-4, never the code string. The SAME map
/// `day_detail_screen.dart`'s `_MoodRow` uses; kept as its own private copy
/// here rather than shared, matching this codebase's existing convention of
/// each screen owning its own small label maps (`day_detail_screen.dart`'s
/// region/painTypes/triggers maps are private and screen-11-specific too).
const List<String> _kMoodLabels = <String>['Low', 'Tired', 'Steady', 'Bright'];

/// Fix round 1, M7: the out-of-range fallback used to be the word `'Mood'`
/// — contract-constrained to 1-4 so unreachable today, but paired with the
/// card's own `'MOOD'` label it would have read as the redundant "MOOD /
/// Mood" the moment a malformed value ever reached the client. The raw
/// integer is honest instead: something WAS logged, just outside the
/// ratified scale, which is a different fact from nothing being logged at
/// all (that case is `'Not logged today'`, decided by the caller).
String _moodLabel(int mood) =>
    (mood >= 1 && mood <= 4) ? _kMoodLabels[mood - 1] : '$mood';

// ---------------------------------------------------------------------------
// DashboardScreen
// ---------------------------------------------------------------------------

/// Screen 8 — the Home tab's branch root (`app_router.dart`, `Routes.home`).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final dashboardAsync = ref.watch(dashboardControllerProvider);

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: dashboardAsync.when(
          loading: () => Center(
            child: CircularProgressIndicator(
              color: c.accent,
              semanticsLabel: 'Loading',
            ),
          ),
          // Never `error.message`: this screen renders health data
          // (pain/mood) and a name, so it follows screen 31's precedent
          // rather than day_detail/cycle_calendar's — the failure's own
          // message can carry a server `detail` string.
          error: (error, _) => LumenErrorRetry(
            message: 'Something went wrong. Please try again.',
            onRetry: () => ref.invalidate(dashboardControllerProvider),
          ),
          data: (result) => _Body(result: result),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — handles Fresh / Stale / NetworkRequired (screen 31's own pattern)
// ---------------------------------------------------------------------------

class _Body extends ConsumerWidget {
  const _Body({required this.result});
  final CacheResult<DashboardView> result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fix round 1, M9: an EXHAUSTIVE switch over the sealed CacheResult
    // union. The original shape here — `result is Fresh<…> ? … :
    // (result as Stale<…>).value` — is screen 31's own, copied verbatim,
    // and it throws a runtime cast exception on any FUTURE CacheResult
    // variant instead of failing to compile; `switch` over a sealed class
    // is checked exhaustively by the analyzer, so a fourth subtype becomes
    // a build error here rather than a production crash.
    return switch (result) {
      NetworkRequired() => const _NetworkRequiredBody(),
      Fresh(:final value) => _LoadedBody(view: value, isStale: false),
      Stale(:final value) => _LoadedBody(view: value, isStale: true),
    };
  }
}

// ---------------------------------------------------------------------------
// Loaded body — Fresh or Stale, both rendered the same way
// ---------------------------------------------------------------------------

/// Fix round 1, M4: wraps the content in the same `RefreshIndicator` +
/// `AlwaysScrollableScrollPhysics` pattern `profile_screen.dart` uses. The
/// stale notice below reads "connect to refresh", but before this fix
/// nothing on screen 8 could actually refresh anything — no pull gesture,
/// no retry in this body, and because the Home branch lives inside the
/// shell's `IndexedStack`, switching tabs away and back does not rebuild
/// the controller either. Without a real refresh path a stale dashboard
/// stayed stale for the rest of the session while promising otherwise.
/// `ref.invalidate` + re-read is a plain GET re-fetch, not a write — the
/// same online-only-reads reasoning `profile_screen.dart`'s own comment
/// states, and this task still writes nothing to the API.
class _LoadedBody extends ConsumerWidget {
  const _LoadedBody({required this.view, required this.isStale});
  final DashboardView view;
  final bool isStale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final greeting = ref.watch(greetingTimeOfDayProvider);

    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(dashboardControllerProvider);
        return ref.read(dashboardControllerProvider.future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isStale) ...[_StaleNotice(c: c), const SizedBox(height: 10)],
            _DateLine(date: view.today),
            const SizedBox(height: 2),
            _GreetingLine(greeting: greeting, displayName: view.displayName),
            const SizedBox(height: 14),
            // Fix round 1, M5: the response's OWN `unavailableReason`, not a
            // hard-coded `null` — see `DashboardView.phaseUnavailableReason`'s
            // dartdoc for why the distinction matters even though every P4a
            // account renders the same neutral copy today.
            LumenPhaseUnavailable(reason: view.phaseUnavailableReason),
            const SizedBox(height: 12),
            // IntrinsicHeight, not a bare `Row(crossAxisAlignment: stretch)`:
            // this Row sits inside a Column inside a SingleChildScrollView, so
            // it receives an UNBOUNDED height from its parent. `stretch` asks
            // each child to fill the Row's own cross-axis (height) extent —
            // fine when that extent is bounded, but propagating "infinite" to
            // each card crashes layout (`BoxConstraints forces an infinite
            // height`). `IntrinsicHeight` measures the children's natural
            // height first and gives the Row THAT as a bounded extent, so
            // `stretch` still makes both cards match the taller one's height
            // (the mockup's `.cards{display:grid}` behaviour) without ever
            // asking anything to be infinitely tall.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _PainCard(
                      todayPain: view.todayPain,
                      yesterdayPain: view.yesterdayPain,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _MoodCard(todayMood: view.todayMood)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Network-required body
// ---------------------------------------------------------------------------

class _NetworkRequiredBody extends ConsumerWidget {
  const _NetworkRequiredBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: c.muted, size: 40),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                'Connect to load your dashboard',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your dashboard requires a network connection\nand no cached '
              'data is available.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
            const SizedBox(height: 16),
            LumenRetryButton(
              label: 'Retry',
              onPressed: () => ref.invalidate(dashboardControllerProvider),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stale notice
// ---------------------------------------------------------------------------

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.c});
  final LumenColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.sageSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Showing cached data — connect to refresh',
        style: TextStyle(fontSize: 11, color: c.sage),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date line and greeting
// ---------------------------------------------------------------------------

/// `"Thursday, April 9"` — from [DashboardView.today], which the controller
/// reads once via `sessionTodayProvider` (the server's own day, D-12), never
/// the device clock. Sentence case, not the mockup's `text-transform:
/// uppercase` `.hi`: that treatment reads naturally on a short eyebrow tag
/// ("SETTINGS", the weekday-only label above screen 11's day number) but not
/// on a full weekday-plus-date sentence — a deliberate departure from the
/// mockup's CSS, the same kind `day_detail_screen.dart` already documents
/// for its own section headers.
class _DateLine extends StatelessWidget {
  const _DateLine({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Text(
      '${LumenFormats.weekdayName(date)}, ${LumenFormats.monthDay(date)}',
      style: TextStyle(fontSize: 11, color: c.muted, letterSpacing: 1),
    );
  }
}

/// `"Good morning, Maya"` — or `"Good morning"` alone when [displayName] is
/// null/blank, never an empty slot or the literal `"null"`.
///
/// [greeting] is read from `greetingTimeOfDayProvider`
/// (`core/time/greeting_clock.dart`) by [_Body], not computed here — that
/// wall-clock courtesy text carries no clinical meaning and answers no
/// question D-12 governs, but a WIDGET calling the bare function directly
/// would leave a golden/semantics test at the mercy of whatever hour the
/// suite happens to run at; the provider seam is what a test overrides
/// instead.
class _GreetingLine extends StatelessWidget {
  const _GreetingLine({required this.greeting, required this.displayName});
  final String greeting;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final name = displayName?.trim();
    final text = (name != null && name.isNotEmpty)
        ? '$greeting, $name'
        : greeting;

    return Text(
      text,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: c.ink),
    );
  }
}

// ---------------------------------------------------------------------------
// Pain / Mood cards
// ---------------------------------------------------------------------------

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 9, color: c.muted, letterSpacing: 0.5),
    );
  }
}

/// [MergeSemantics], the same choice `profile_screen.dart`'s `_UserCard` and
/// `LumenPhaseUnavailable` make for an informational block with no `onTap`:
/// one merged unit ("Pain today, 3 / 10, Down, vs yesterday") rather than
/// three or four disconnected announcements. Never `Semantics(button: true)`
/// — nothing is wired behind either card.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.input,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: child,
        ),
      ),
    );
  }
}

/// Card 1 — "Pain today". Renders `<pain> / 10` — **never a falsiness
/// test**: `pain: 0` is a real logged value (D-08) and must render as
/// `"0 / 10"`, exactly like a 3.
///
/// `"↓ vs yesterday"` — rendered as a decorative down-arrow [Icon] (never a
/// literal `↓` glyph in a [Text]: the dingbat rule is an allowlist, and
/// U+2193 is not on it) plus the words "vs yesterday" — ships ONLY when
/// [todayPain] is a strictly LOWER number than [yesterdayPain], both
/// present. It is arithmetic on the user's own two recorded numbers, not a
/// clinical inference, but the arithmetic still has to run: rendering it
/// whenever both values merely exist (regardless of direction) would
/// sometimes announce a drop that never happened. Anything else — either
/// value missing, no drop, an increase, no change — renders nothing here.
/// Never `"—"`, never `"no change"`: an evaluative word for a state that
/// is not a drop is exactly the kind of inference this screen avoids
/// everywhere else.
class _PainCard extends StatelessWidget {
  const _PainCard({required this.todayPain, required this.yesterdayPain});
  final int? todayPain;
  final int? yesterdayPain;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final pain = todayPain; // never `?? 0` — D-08.
    final yesterday = yesterdayPain;
    final showsDrop = pain != null && yesterday != null && pain < yesterday;

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Pain today'),
          const SizedBox(height: 2),
          Text(
            pain != null ? '$pain / 10' : 'Not logged today',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          if (showsDrop) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_downward,
                  size: 10,
                  color: c.sage,
                  semanticLabel: 'Down',
                ),
                const SizedBox(width: 2),
                Text(
                  'vs yesterday',
                  style: TextStyle(fontSize: 10, color: c.sage),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Card 2 — "Mood", replacing the mockup's Energy (D-10: `energy` has no
/// writer and no CHECK in P4a). Mood IS on the same row `pain` is, matching
/// the "Pain & mood" pairing `day_detail_screen.dart`'s T16 established.
class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.todayMood});
  final int? todayMood;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final mood = todayMood;

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Mood'),
          const SizedBox(height: 2),
          Text(
            mood != null ? _moodLabel(mood) : 'Not logged today',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
        ],
      ),
    );
  }
}
