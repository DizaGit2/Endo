import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/cycle_setup_controller.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

/// The seven single-letter weekday headings, by [DateTime] weekday constant.
///
/// The mockup's fixed `S M T W T F S` row is an English, Sunday-first artifact,
/// not the spec: the ORDER comes from [LumenFormats.orderedWeekdays], which is
/// Monday-first under es-ES (D-05). Keeping the letters here and the order there
/// is what lets the grid rotate without a string being translated —
/// `lumen_formats.dart` says so at [LumenFormats.orderedWeekdays] and
/// deliberately returns no labels.
const Map<int, String> _weekdayInitials = <int, String>{
  DateTime.monday: 'M',
  DateTime.tuesday: 'T',
  DateTime.wednesday: 'W',
  DateTime.thursday: 'T',
  DateTime.friday: 'F',
  DateTime.saturday: 'S',
  DateTime.sunday: 'S',
};

// ---------------------------------------------------------------------------
// CycleSetupScreen
// ---------------------------------------------------------------------------

/// Screen 3 — "When did your last period start?" (onboarding step 3 of 7).
///
/// The **one mandatory step** of the flow (D-02) and the screen a user returns
/// to in order to correct a mistyped date. It is a step BODY, not a route: the
/// eyebrow, the back affordance, the dot row and the padding all belong to
/// `OnboardingShellScreen`, which mounts this in place of the `cycle` arm of
/// its exhaustive switch.
///
/// ## What it validates, and what it refuses to
///
/// Nothing clinical. The C-03 cycle- and period-length bounds are
/// clinician-UNSIGNED PO-interim values whose only lawful home is P6's rule
/// seed; they appear nowhere in `backend/src` and nowhere under `lib/` — not as
/// a validator, not as a constant, not as a numeral in a comment. The
/// **sanity band** (`CycleSettingsSanityBand`, server-side) is not a bound at
/// all: an out-of-band value is stored and answered with a 200 carrying a
/// warning code, so it is rendered here as an advisory after a successful save
/// and never as a validator.
///
/// Two rules do reach this screen, and both are the endpoint's own:
///
///  * `lastPeriodStart` is required on every post, so Continue is inert without
///    one — a rule about whether an answer exists, not about its value;
///  * `lastPeriodStart > today` is a 400, so the calendar stops offering days
///    past the server's `today`. When that read failed there is no bound and no
///    guess — see [CycleSetupForm.today].
///
/// The backdate floor (account creation minus two years) cannot be evaluated
/// here at all, because no endpoint returns `users.created_at`; it reaches the
/// user as the server's own 400 under the calendar.
class CycleSetupScreen extends ConsumerWidget {
  const CycleSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final form = ref.watch(cycleSetupControllerProvider);

    return form.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(
            color: c.accent,
            semanticsLabel: 'Loading',
          ),
        ),
      ),
      // Reached only when the screen has no month to open the calendar on: no
      // anchor from the resume read AND no `today` from the server. There is no
      // honest partial screen to draw, and the one thing left to derive a month
      // from is the device clock, which D-12 forbids.
      error: (error, _) => LumenErrorRetry(
        message: error is Failure
            ? error.message
            : 'Something went wrong. Please try again.',
        onRetry: () => ref.invalidate(cycleSetupControllerProvider),
      ),
      data: (value) => _Body(form: value),
    );
  }
}

// ---------------------------------------------------------------------------
// The form
// ---------------------------------------------------------------------------

class _Body extends ConsumerWidget {
  const _Body({required this.form});

  final CycleSetupForm form;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final locale = ref.watch(localeProvider);
    final controller = ref.read(cycleSetupControllerProvider.notifier);

    final failure = form.failure;
    final rejected = failure is ValidationFailure ? failure : null;
    final bannerMessage = _bannerMessage(failure);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'When did your last period start?',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w500,
              color: c.ink,
              letterSpacing: -0.3,
            ),
          ),
        ),

        const SizedBox(height: 6),

        Text(
          "We'll predict your phases from here.",
          style: TextStyle(fontSize: 12, color: c.muted, height: 1.5),
        ),

        const SizedBox(height: 18),

        _MonthGrid(
          form: form,
          locale: locale,
          onChoose: controller.chooseDay,
          onPrevious: controller.showPreviousMonth,
          onNext: controller.showNextMonth,
        ),

        // The server's own message for the anchor — how the backdate floor and
        // the no-future-dates rule reach the user, since the client can
        // evaluate neither.
        if (rejected?.messageFor('lastPeriodStart') != null) ...[
          const SizedBox(height: 6),
          _FieldMessage(rejected!.messageFor('lastPeriodStart')!),
        ],

        const SizedBox(height: 14),

        const _FieldLabel('Average cycle length'),
        const SizedBox(height: 6),
        _CycleLengthChips(
          form: form,
          locale: locale,
          onChoose: controller.chooseCycleLength,
        ),
        if (rejected?.messageFor('avgCycleLengthDays') != null) ...[
          const SizedBox(height: 6),
          _FieldMessage(rejected!.messageFor('avgCycleLengthDays')!),
        ],

        const SizedBox(height: 14),

        const _FieldLabel('Regularity'),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            for (final regularity in CycleRegularity.values) ...<Widget>[
              if (regularity != CycleRegularity.values.first)
                const SizedBox(width: 8),
              Expanded(
                child: _Chip(
                  text: regularity.label,
                  selected: form.answers.regularity == regularity,
                  onTap: () => controller.chooseRegularity(regularity),
                ),
              ),
            ],
          ],
        ),
        if (rejected?.messageFor('regularity') != null) ...[
          const SizedBox(height: 6),
          _FieldMessage(rejected!.messageFor('regularity')!),
        ],

        // The mockup's `.btn { margin-top:auto }`. What it pushes against is
        // [OnboardingStepSlot], which is why this is a `Spacer` and not a
        // `SizedBox` of some measured height: the CTA rides the bottom of the
        // step on every surface, and takes no space at all on one too short
        // for the body, which scrolls instead.
        const Spacer(),

        // After a SUCCESSFUL save, never before one: the band does not block a
        // write, so there is nothing to say until the value is stored.
        for (final code in form.warnings)
          if (cycleWarningMessage(code) case final message?) ...<Widget>[
            const SizedBox(height: 16),
            _Advisory(message),
          ],

        if (bannerMessage != null) ...<Widget>[
          const SizedBox(height: 16),
          LumenErrorBanner(message: bannerMessage),
        ],

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            // Inert without an anchor. That is the endpoint's own rule
            // (`lastPeriodStart` is required on every post) and the one
            // mandatory answer of onboarding — not a bound on its value.
            onPressed: form.answers.lastPeriodStart == null || form.submitting
                ? null
                : controller.submit,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              elevation: 0,
            ),
            child: form.submitting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.surface,
                      // The shell's own spinner label, reused rather than
                      // invented: no copy for this state exists in the mockup
                      // or in `definitions.md`.
                      semanticsLabel: 'Loading',
                    ),
                  )
                : const Text('Continue'),
          ),
        ),
      ],
    );
  }
}

/// What the banner above the CTA says, or null when there is nothing wrong.
///
/// Same shape as screen 2's: the banner is this body's only live region, so it
/// is never suppressed in favour of the per-field messages, which are ordinary
/// nodes and stay silent until swiped onto. For a [ValidationFailure] it
/// prefers the server's reserved cross-field messages, which name no input and
/// would otherwise render nowhere.
String? _bannerMessage(Failure? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure) {
    final crossField = failure.requestMessages;
    return crossField.isEmpty ? failure.message : crossField.first;
  }
  return failure.message;
}

// ---------------------------------------------------------------------------
// The calendar
// ---------------------------------------------------------------------------

/// The inline month grid the mockup draws, rotated to the locale's own week.
///
/// **The mockup's Sunday-first `S M T W T F S` header is not the spec.**
/// [LumenFormats.firstDayOfWeek] is Monday under es-ES, the D-03 primary
/// locale, and [LumenFormats.leadingBlankDays] is what keeps the 1st of the
/// month in the right column — getting that constant wrong shifts every date by
/// one, which is why it lives in the formatter once rather than in each of
/// screens 3, 10 and 11.
///
/// **The mockup's `.r` in-range fill is deliberately not drawn.** It shades the
/// inferred period around the selection, and inferring a period length or a
/// phase is C-01/C-04 work that belongs to the phase engine (P6). Drawing it
/// here would mean the client computing a clinical answer nobody has signed.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.form,
    required this.locale,
    required this.onChoose,
    required this.onPrevious,
    required this.onNext,
  });

  final CycleSetupForm form;
  final String locale;
  final void Function(Date day) onChoose;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final materialLocalizations = MaterialLocalizations.of(context);
    final month = form.visibleMonth;
    // Day 0 of the following month is the last day of this one — right for
    // 30/31-day months and for both kinds of February.
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = LumenFormats.leadingBlankDays(month, locale);
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return Container(
      decoration: BoxDecoration(
        color: c.input,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _MonthStep(
                icon: Icons.chevron_left,
                // The platform's own name for this control, translated wherever
                // Flutter is — and on the ICON, not on `tooltip:`, because a
                // tooltip builds its own semantics node outside the button's.
                label: materialLocalizations.previousMonthTooltip,
                onPressed: onPrevious,
              ),
              Expanded(
                child: Text(
                  LumenFormats.monthYear(month, locale),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
              ),
              _MonthStep(
                icon: Icons.chevron_right,
                label: materialLocalizations.nextMonthTooltip,
                onPressed: form.canShowNextMonth ? onNext : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Excluded: every day cell announces its own full date, so seven
          // single letters in the reading order are noise.
          ExcludeSemantics(
            child: Row(
              children: <Widget>[
                for (final weekday in LumenFormats.orderedWeekdays(locale))
                  Expanded(
                    child: Text(
                      _weekdayInitials[weekday]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: c.muted.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var row = 0; row < rows; row++)
            Row(
              children: <Widget>[
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: _cell(row * 7 + column - leading, daysInMonth),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int dayIndex, int daysInMonth) {
    if (dayIndex < 0 || dayIndex >= daysInMonth) {
      return const SizedBox(height: 26);
    }
    final day = dayIndex + 1;
    return _DayCell(
      date: Date(form.visibleMonth.year, form.visibleMonth.month, day),
      form: form,
      locale: locale,
      onChoose: onChoose,
    );
  }
}

class _MonthStep extends StatelessWidget {
  const _MonthStep({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return IconButton(
      icon: Icon(icon, size: 18, semanticLabel: label),
      color: c.muted,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onPressed,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.form,
    required this.locale,
    required this.onChoose,
  });

  final Date date;
  final CycleSetupForm form;
  final String locale;
  final void Function(Date day) onChoose;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final selected = form.answers.lastPeriodStart == date;
    final choosable = form.canChoose(date);
    // The full date, locale-ordered: "6" alone tells a screen-reader user
    // nothing about which month or year they are in.
    final announced = LumenFormats.date(date.toDateTime(), locale);
    final number = LumenFormats.decimal(date.day, locale, decimalDigits: 0);

    final cell = Container(
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? c.accent : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        number,
        style: TextStyle(
          fontSize: 10,
          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          color: selected
              ? c.surface
              : choosable
              ? c.ink
              : c.muted.withValues(alpha: 0.4),
        ),
      ),
    );

    if (!choosable) {
      // Announced, but not as a control: the server refuses a future anchor, so
      // offering a tap here would be a promise the screen cannot keep.
      return Semantics(label: announced, excludeSemantics: true, child: cell);
    }

    void choose() => onChoose(date);

    // excludeSemantics drops the child GestureDetector's tap action from the
    // tree, so this Semantics needs its own onTap wired to the SAME callback.
    return Semantics(
      button: true,
      selected: selected,
      label: announced,
      excludeSemantics: true,
      onTap: choose,
      child: GestureDetector(
        onTap: choose,
        behavior: HitTestBehavior.opaque,
        child: cell,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The chips
// ---------------------------------------------------------------------------

/// The five quick picks, plus whatever the user has actually got.
///
/// The column is a free positive `smallint` and screen 32 sets values outside
/// the mockup's five, so a stored value that is not one of them gets a chip of
/// its own rather than being hidden behind an unselected row — hiding it is
/// what would make the next save look like a fresh answer. The chip is derived
/// from what is **stored** as well as from what is chosen, so trying a quick
/// pick never destroys the way back to it.
///
/// **This screen offers no free-text entry**: the affordance would need a
/// label, a sheet title and a confirm, none of which exists in the mockup or in
/// `definitions.md`.
class _CycleLengthChips extends StatelessWidget {
  const _CycleLengthChips({
    required this.form,
    required this.locale,
    required this.onChoose,
  });

  final CycleSetupForm form;
  final String locale;
  final void Function(int days) onChoose;

  @override
  Widget build(BuildContext context) {
    final chosen = form.answers.avgCycleLengthDays;
    // The STORED value gets a chip too, not just the chosen one. Deriving the
    // row from the selection alone makes an out-of-list answer a one-way door:
    // tap 30 to see what it looks like and the 33 chip is gone, with nothing on
    // screen offering it back and Continue now writing 30. A `Set` because the
    // two are usually the same number.
    final stored = form.saved.avgCycleLengthDays;
    final picks = <int>{...kAvgCycleLengthQuickPicks, ?chosen, ?stored}.toList()
      ..sort();

    return Row(
      children: <Widget>[
        for (final days in picks) ...<Widget>[
          if (days != picks.first) const SizedBox(width: 8),
          Expanded(
            child: _Chip(
              text: LumenFormats.decimal(days, locale, decimalDigits: 0),
              // "26" alone is not an answer to anything. The unit is the one
              // `definitions.md` gives these chips, and the one screen 32
              // renders ("29 days").
              announced: '$days days',
              selected: chosen == days,
              onTap: () => onChoose(days),
            ),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.selected,
    required this.onTap,
    this.announced,
  });

  final String text;
  final String? announced;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Semantics(
      button: true,
      selected: selected,
      label: announced ?? text,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.input,
            border: Border.all(color: selected ? c.accent : c.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? c.accent : c.ink,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small parts
// ---------------------------------------------------------------------------

/// The mockup's `.lb` field label — uppercased by presentation, announced in
/// sentence case.
///
/// The split is P4b-T8's lesson, applied one widget over: an all-caps run is
/// spelled out letter by letter by many screen readers, so what is drawn and
/// what is announced are deliberately different strings.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: c.muted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// One field's rejection message, in the server's own words.
class _FieldMessage extends StatelessWidget {
  const _FieldMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Text(
      message,
      style: TextStyle(fontSize: 12, color: c.accent, height: 1.4),
    );
  }
}

/// A non-blocking note about a save that already succeeded.
///
/// Deliberately not [LumenErrorBanner]: nothing failed, nothing needs retrying,
/// and dressing a stored value as an error is what turns a hint into the entry
/// blocker rider 7 forbids. It is a live region because it appears in response
/// to an action the user just took.
class _Advisory extends StatelessWidget {
  const _Advisory(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.input,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Text(
          message,
          style: TextStyle(fontSize: 13, color: c.muted, height: 1.4),
        ),
      ),
    );
  }
}
