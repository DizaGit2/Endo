import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// One field's rejection message, in the server's own words.
///
/// Promoted from the `_FieldMessage` that existed byte-identically in
/// `cycle_setup_screen.dart` (screen 3) and `baseline_screen.dart` (screen 4)
/// — P4b-T5c, before screens 5-7 added three more copies.
///
/// Deliberately NOT paraphrased at the call site: some of these rules cannot
/// be evaluated here at all. Screen 3's backdate floor is the USER's
/// `users.created_at - 2 years` (`UserDayContext.cs:47`), and no endpoint
/// returns that field — five schemas do expose a `createdAt`
/// (`CycleDayLogResponse`, `CycleEventResponse`, `CycleSettingsResponse`,
/// `RegisterDeviceResponse`, `SymptomResponse`), but every one of them is the
/// creation stamp of a RECORD, not of the account, so none of them can
/// reconstruct the floor. The server's sentence is therefore the only wording
/// guaranteed to describe what was actually refused.
///
/// It is also deliberately not a live region: the screens render it under a
/// `LumenErrorBanner`, which is one, so the arrival of a rejection announces
/// once rather than once per rejected field.
///
/// CSS equivalent: `color: var(--ac); font-size: 12px; line-height: 1.4`.
class LumenFieldMessage extends StatelessWidget {
  const LumenFieldMessage(this.message, {super.key});

  /// The server's message for one field, rendered unchanged.
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
