import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_field_label.dart';

import '../support/harness.dart';

/// The label in the arrangement both onboarding screens draw it in — above the
/// control it names — and in both of its variants, so the image pins the muted
/// colour, the 11 px letter-spaced run and the 6 px gap beneath it.
///
/// Both variants appear, so an `announce: false` label is inside the committed
/// image rather than outside it — but note what that does and does not prove.
/// The rows carry different strings and each image is compared against its own
/// committed PNG, so nothing here compares one row to another. The claim that
/// `announce` changes nothing about what is painted is proved in
/// `lumen_field_label_test.dart:83-104`, which pumps the SAME text under both
/// values of the flag and compares style and size.
Widget _labels(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  Widget field(String label, String value, {bool announce = true}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      LumenFieldLabel(label, announce: announce),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.input,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Text(value, style: TextStyle(fontSize: 13, color: c.ink)),
      ),
    ],
  );

  return ColoredBox(
    color: c.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 44, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          field('Average cycle length', '28 days'),
          const SizedBox(height: 14),
          field('Height', '165 cm', announce: false),
          const SizedBox(height: 14),
          field('Endometriosis status', 'Diagnosed'),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenFieldLabel',
    fileName: 'lumen_field_label',
    build: (brightness) =>
        goldenApp(home: _labels(brightness), brightness: brightness),
  );
}
