import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/core/locale/lumen_material_localizations.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/baseline_controller.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_field_label.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';
import 'package:lumen/shared/widgets/lumen_selectable_row.dart';

// ---------------------------------------------------------------------------
// The date-of-birth range
// ---------------------------------------------------------------------------

/// The earliest date the date-of-birth picker offers.
///
/// **This is a type domain, not an age gate, and the distinction is the whole
/// point.** `docs/ARCHITECTURE.md:62` puts it in one sentence — "There is no
/// age gate and no lower bound on `dob` beyond `DateOnly` itself: C-12 makes
/// the population a design target and *"NOT a data-entry/age gate"*" — and the
/// backend says the same twice more: `OnboardingStepResult.cs:258-260` ("there
/// is deliberately no lower bound on `dob` at all beyond `DateOnly` itself")
/// and `OnboardingStepsService.cs:167-171`, which adds that a "born before
/// 19xx" floor *would be* an age gate, which C-12 forbids.
///
/// L-01 (the minimum-age / eligibility question) is **unanswered**, and P4b's
/// instruction is to neither invent a gate nor imply one exists.
///
/// `showDatePicker` requires a `firstDate`, so the only honest value is the
/// bottom of the same domain the column has: `DateOnly.MinValue` is year 1, and
/// so is this. Anything friendlier — 1900, 1920, "120 years ago" — would be a
/// floor this product has decided not to have, drawn where a user can see it.
final DateTime kDobFloor = DateTime(1);

// ---------------------------------------------------------------------------
// BaselineScreen
// ---------------------------------------------------------------------------

/// Screen 4 — "A few baseline details" (onboarding step 4 of 7).
///
/// The first **skippable** step (D-02), and everything about how it submits
/// follows from that: "skip" means *not calling the endpoint*, because
/// `POST /onboarding/baseline` answers 400 to a body carrying none of its six
/// fields. So Continue is always enabled and posts only what changed — see
/// [BaselineController.submit].
///
/// It is a step BODY, not a route: the eyebrow, the back affordance, the dot
/// row and the padding all belong to `OnboardingShellScreen`, which mounts this
/// in place of the `baseline` arm of its exhaustive switch.
///
/// ## What it collects, and what it deliberately does not
///
/// The mockup (`Screens/screen_04_baseline.html`) draws four things: Age,
/// Height, Weight and an Endometriosis-status radio group. **Age is rendered
/// here as a date of birth**, because that is what the model stores (`dob`, a
/// `DateOnly?`) and age is derived from it — a year-only control would invent a
/// day the user never gave.
///
/// `SaveBaselineRequest` carries two more members, and **this screen collects
/// neither**:
///
///  * **`rasrmStage`** (`int?`, 1-4, rendered I-IV). The mockup draws no stage
///    control, and `definitions.md` carries no extraction for screen 4 at all,
///    so there is no ratified label, option set or helper sentence for one. Authoring them
///    would be authoring *clinical* wording: C-14 records that rASRM **does not
///    correlate with pain**, which rules out every "higher stage = worse"
///    framing an implementer would reach for, and names the four stages
///    minimal / mild / moderate / severe — never "extensive". Reported rather
///    than invented.
///  * **`diagnosedOn`** (a `String?` of exact form `yyyy-MM`, month precision —
///    NOT a `Date?`, because the generated `DateSerializer` calls
///    `DateTime.parse`, which throws on `"2026-08"`, §C.0.2). The mockup draws
///    no diagnosis-month control either. It can still arrive here on the
///    prefill, and nothing on this screen parses it — `LumenWire` owns the
///    hand-parse for whichever surface eventually shows it.
///
/// Surgeries ("1 laparoscopy", screen 31) have no storage column at all and are
/// deferred with C-14.
///
/// ## What it validates, and what it refuses to
///
/// Two structural rules reach this screen, and both mirror a storage domain
/// rather than a clinical one:
///
///  * `dob > today` is a 400 (`OnboardingStepsService.cs:172-173`), so the
///    picker's upper bound is the server's `today` (D-12) and there is no
///    picker at all without it. There is **no lower bound** — see [kDobFloor].
///  * `weightKg` is stored to one decimal place and extra precision is
///    **rejected, never rounded** (`OnboardingStepsService.cs:192-197`,
///    `BaselineStructuralDomain.MaxWeightDecimals`), so the field will not take
///    a second decimal digit. Rounding it away here would store a number the
///    user did not type — which is exactly what the server refuses to do.
///
/// Everything else — the ranges on height and weight, the endo-status
/// vocabulary — is left to the server's own 400, whose message is rendered
/// under the field that earned it. No range is restated on this side of the
/// wire.
class BaselineScreen extends ConsumerWidget {
  const BaselineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final form = ref.watch(baselineControllerProvider).value;

    // There is no error arm, and that is deliberate: neither read can take this
    // step away. A failed profile read leaves the answers unknown and a failed
    // `today` closes the date picker, but the step is skippable and skipping
    // needs no network — a whole-surface retry would hide the one action an
    // offline user can still complete. See [BaselineController].
    if (form == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(
            color: c.accent,
            semanticsLabel: 'Loading',
          ),
        ),
      );
    }

    return _Body(form: form);
  }
}

// ---------------------------------------------------------------------------
// The form
// ---------------------------------------------------------------------------

/// Stateful for the two [TextEditingController]s alone.
///
/// They are seeded ONCE, from the form the resume read produced, and never
/// re-seeded from state afterwards: rewriting a field's text while somebody is
/// typing in it moves their cursor. A successful save advances to step 5, so
/// there is no state change this screen has to re-render text for.
class _Body extends ConsumerStatefulWidget {
  const _Body({required this.form});

  final BaselineForm form;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late final TextEditingController _height;
  late final TextEditingController _weight;

  @override
  void initState() {
    super.initState();
    final locale = ref.read(localeProvider);
    final answers = widget.form.answers;
    _height = TextEditingController(
      text: answers.heightCm == null
          ? ''
          : LumenFormats.decimal(answers.heightCm!, locale, decimalDigits: 0),
    );
    _weight = TextEditingController(
      text: answers.weightKg == null
          ? ''
          : LumenFormats.decimal(answers.weightKg!, locale),
    );
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final locale = ref.watch(localeProvider);
    final controller = ref.read(baselineControllerProvider.notifier);
    final form = widget.form;

    final failure = form.failure;
    final rejected = failure is ValidationFailure ? failure : null;
    final bannerMessage = _bannerMessage(failure);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            'A few baseline details',
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
          'Used to personalize hormone ranges. Edit anytime.',
          style: TextStyle(fontSize: 12, color: c.muted, height: 1.5),
        ),

        const SizedBox(height: 18),

        // The mockup's `.r2` two-column row. Its left cell is "Age"; what the
        // model stores is a date of birth, and age is derived from it.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const LumenFieldLabel('Date of birth', announce: false),
                  const SizedBox(height: 6),
                  _DobField(
                    form: form,
                    locale: locale,
                    onPick: () => _pickDob(context, form, controller, locale),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const LumenFieldLabel('Height', announce: false),
                  const SizedBox(height: 6),
                  LumenInputField(
                    controller: _height,
                    label: 'Height',
                    // The mockup draws no placeholder — a `.fld` box holds a
                    // value and a unit, and nothing else.
                    hint: '',
                    // The mockup's `.fu` span. A suffix rather than a hint
                    // because a hint vanishes as soon as the field has
                    // content, and a prefilled `165` with no unit beside it is
                    // the state a returning user starts in. D-06 is
                    // metric-only in v1.
                    suffixText: 'cm',
                    keyboardType: TextInputType.number,
                    enabled: !form.submitting,
                    // A whole number of centimetres: `heightCm` is an `int?`.
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (String text) => controller.setHeightCm(
                      LumenFormats.parseDecimal(text, locale)?.round(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        if (rejected?.messageFor('dob') != null) ...<Widget>[
          const SizedBox(height: 6),
          LumenFieldMessage(rejected!.messageFor('dob')!),
        ],
        if (rejected?.messageFor('heightCm') != null) ...<Widget>[
          const SizedBox(height: 6),
          LumenFieldMessage(rejected!.messageFor('heightCm')!),
        ],

        const SizedBox(height: 14),

        const LumenFieldLabel('Weight', announce: false),
        const SizedBox(height: 6),
        LumenInputField(
          controller: _weight,
          label: 'Weight',
          hint: '',
          suffixText: 'kg',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: !form.submitting,
          inputFormatters: <TextInputFormatter>[
            _OneDecimalPlace(LumenFormats.decimalSeparator(locale)),
          ],
          onChanged: (String text) => controller.setWeightKg(
            LumenFormats.parseDecimal(text, locale),
          ),
        ),
        if (rejected?.messageFor('weightKg') != null) ...<Widget>[
          const SizedBox(height: 6),
          LumenFieldMessage(rejected!.messageFor('weightKg')!),
        ],

        const SizedBox(height: 14),

        const LumenFieldLabel('Endometriosis status'),
        const SizedBox(height: 6),
        for (final status in EndoStatus.values) ...<Widget>[
          if (status != EndoStatus.values.first) const SizedBox(height: 6),
          _StatusOption(
            status: status,
            selected: form.answers.endoStatus == status,
            onTap: () => controller.chooseEndoStatus(status),
          ),
        ],
        if (rejected?.messageFor('endoStatus') != null) ...<Widget>[
          const SizedBox(height: 6),
          LumenFieldMessage(rejected!.messageFor('endoStatus')!),
        ],

        // The mockup's `.btn { margin-top:auto }`. What it pushes against is
        // `OnboardingStepSlot`, which is why this is a `Spacer` and not a
        // `SizedBox` of some measured height.
        const Spacer(),

        if (bannerMessage != null) ...<Widget>[
          const SizedBox(height: 16),
          LumenErrorBanner(message: bannerMessage),
        ],

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            // Never disabled for want of an answer: the step is optional and
            // Continue is the only way past it. It is inert only while a save
            // is in flight.
            onPressed: form.submitting ? null : controller.submit,
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

  /// Opens the platform date picker, bounded above by the server's `today` and
  /// below by nothing.
  ///
  /// `showDatePicker` rather than a bottom sheet, deliberately: every string in
  /// it (the title, Cancel, OK, the month and weekday names) belongs to
  /// `MaterialLocalizations`, so the control costs no authored copy, whereas a
  /// sheet would need a title and a confirm that exist in neither the mockup
  /// nor `definitions.md`. `DatePickerEntryMode.calendarOnly` removes the
  /// keyboard-entry toggle — that mode is the `TextField(labelText:)` the phase
  /// keeps out of dialogs — and `DatePickerMode.year` opens on the year grid,
  /// which is the only sane first step for a date of birth.
  ///
  /// Three arguments here are load-bearing, and two of them were defects:
  ///
  ///  * **`initialDate` is null when nothing is stored.** `_handleOk` pops
  ///    `_selectedDate.value`, which starts as `initialDate`
  ///    (`date_picker.dart:468,507`), so seeding it meant an OK tapped with
  ///    zero interaction returned that seed — writing **today** as a date of
  ///    birth the user never entered, on a field §C.0.1 gives no way to clear.
  ///    Null makes that same tap return null, and [chooseDob] never runs.
  ///  * **`currentDate` is the SERVER's today, and omitting it read the device
  ///    clock.** Unset, the dialog falls back to `calendarDelegate.now()`
  ///    (`date_picker.dart:338`) — which D-12 forbids, and which this screen
  ///    then *styles* through `todayBorder`, so a phone a day fast would ring
  ///    the first day `lastDate` refuses. It also decides what an EMPTY picker
  ///    opens on: `_currentDisplayedMonthDate` is `initialDate ?? currentDate`
  ///    (`calendar_date_picker.dart:217`) and the year grid anchors on that
  ///    (`:372`), so with a year-1 floor this is what keeps the empty case
  ///    two flicks from 1996 instead of two thousand years away.
  ///  * **`Localizations.override` corrects the week start.** The app wires no
  ///    `localizationsDelegates`, so the dialog would resolve
  ///    `DefaultMaterialLocalizations` and draw a Sunday-first week for every
  ///    locale — one screen away from screen 3's Monday-first grid under es-ES.
  ///    R-04 permits English strings; it does not permit a hard-coded week.
  ///    See `lumen_material_localizations.dart`.
  ///
  /// What it still inherits from Material, and does not try to out-engineer:
  /// tapping a YEAR selects that year with the displayed month and the first
  /// available day (`calendar_date_picker.dart:296-317`) before switching to
  /// the day grid. A user who confirms right then records a day they did not
  /// tap — but the header shows the full date they are confirming, so it is a
  /// visible confirmation rather than a silent write, and it is the behaviour
  /// of every Material date picker.
  Future<void> _pickDob(
    BuildContext context,
    BaselineForm form,
    BaselineController controller,
    String locale,
  ) async {
    final bound = form.today;
    if (bound == null) return;
    final upper = bound.toDateTime();

    final picked = await showDatePicker(
      context: context,
      // Null when unanswered — see above. Never a seeded "today".
      initialDate: form.answers.dob?.toDateTime(),
      firstDate: kDobFloor,
      lastDate: upper,
      currentDate: upper,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDatePickerMode: DatePickerMode.year,
      builder: (BuildContext context, Widget? child) {
        final c = Theme.of(context).extension<LumenColors>()!;
        return Localizations.override(
          context: context,
          delegates: <LocalizationsDelegate<dynamic>>[
            LumenMaterialLocalizationsDelegate(
              firstDayOfWeekIndex: materialFirstDayOfWeekIndex(locale),
            ),
          ],
          child: Theme(
            data: Theme.of(context).copyWith(
              datePickerTheme: DatePickerThemeData(
                backgroundColor: c.surface,
                headerBackgroundColor: c.surface,
                headerForegroundColor: c.ink,
                surfaceTintColor: Colors.transparent,
                dividerColor: c.border,
                todayBorder: BorderSide(color: c.accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            child: child!,
          ),
        );
      },
    );

    if (picked == null) return;
    controller.chooseDob(Date(picked.year, picked.month, picked.day));
  }
}

/// What the banner above the CTA says, or null when there is nothing wrong.
///
/// Same shape as screens 2 and 3: the banner is this body's only live region,
/// so it is never suppressed in favour of the per-field messages, which are
/// ordinary nodes and stay silent until swiped onto. For a [ValidationFailure]
/// it prefers the server's reserved cross-field messages — `provide at least
/// one baseline field` is one of those, and it names no input.
String? _bannerMessage(Failure? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure) {
    final crossField = failure.requestMessages;
    return crossField.isEmpty ? failure.message : crossField.first;
  }
  return failure.message;
}

// ---------------------------------------------------------------------------
// The date-of-birth cell
// ---------------------------------------------------------------------------

/// The mockup's `.fld` box, holding a date instead of taking text.
///
/// Empty until the user picks one: there is no placeholder, because a date of
/// birth has no example value the app is entitled to suggest and the mockup's
/// "29 yrs" is a filled-in state, not a prompt.
class _DobField extends StatelessWidget {
  const _DobField({
    required this.form,
    required this.locale,
    required this.onPick,
  });

  final BaselineForm form;
  final String locale;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final dob = form.answers.dob;
    final value = dob == null
        ? ''
        : LumenFormats.date(dob.toDateTime(), locale);

    final box = Container(
      height: 48,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.input,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 14,
          color: form.canPickDob ? c.ink : c.muted.withValues(alpha: 0.6),
        ),
      ),
    );

    if (!form.canPickDob) {
      // Announced, but not as a control: a picker needs an upper bound and the
      // server's `today` is the only sanctioned source of one (D-12). Offering
      // a tap here would be a promise the screen cannot keep.
      return Semantics(
        label: 'Date of birth',
        value: value,
        excludeSemantics: true,
        child: box,
      );
    }

    // excludeSemantics drops the child GestureDetector's tap action from the
    // tree, so this Semantics needs its own onTap wired to the SAME callback.
    return Semantics(
      button: true,
      label: 'Date of birth',
      value: value,
      excludeSemantics: true,
      onTap: onPick,
      child: GestureDetector(
        onTap: onPick,
        behavior: HitTestBehavior.opaque,
        child: box,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The status options
// ---------------------------------------------------------------------------

/// One `.opt` row: a radio dot and the option's label.
///
/// There is no "none of these" and no way to un-choose: the endpoint merges, so
/// a cleared status could not clear the stored one, and `not_applicable` is
/// already the real answer for a user the question does not apply to.
///
/// The box, the selected styling and the button semantics are
/// [LumenSelectableRow]'s (P4b-T5d); the radio dot and the label are this
/// screen's. The announced string is the label, unchanged — it used to be
/// authored under `excludeSemantics: true` and is now the merge of what the row
/// draws, which is the same string.
class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final EndoStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return LumenSelectableRow(
      selected: selected,
      onTap: onTap,
      // The mockup's `.opt` row is tighter than screen 5's `.g` row, so both
      // numbers travel with the call site rather than being averaged into the
      // shared widget.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      borderRadius: 10,
      child: Row(
        children: <Widget>[
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? c.accent : null,
              border: Border.all(
                color: selected ? c.accent : c.border,
                width: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? c.accent : c.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small parts
// ---------------------------------------------------------------------------

/// At most one digit after [separator], and nothing but digits before it.
///
/// The rule is `BaselineStructuralDomain.MaxWeightDecimals` (= 1), and it is
/// enforced at the keyboard rather than at the wire on purpose. The backend
/// **rejects** a second decimal place rather than rounding it away, because
/// "quietly storing 60.4 for a user who typed 60.44 is inventing a datum"
/// (`OnboardingStepsService.cs:192-197`) — and a client that rounded before
/// serialising would be inventing exactly that datum on the server's behalf.
/// Refusing the keystroke is the only option that neither invents a number nor
/// spends a round trip to be told about one.
///
/// `LumenWire.weightKg` still rounds immediately before serialisation, and with
/// this formatter in place it can only ever tidy floating-point representation
/// error — never drop a digit somebody typed.
///
/// No upper bound is imposed: the range is the server's and its 400 says so in
/// its own words.
class _OneDecimalPlace extends TextInputFormatter {
  _OneDecimalPlace(String separator)
    : _pattern = RegExp('^\\d*(${RegExp.escape(separator)}\\d?)?\$');

  final RegExp _pattern;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => _pattern.hasMatch(newValue.text) ? newValue : oldValue;
}
