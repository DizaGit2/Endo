// Accessibility tests for LumenInputField (P4b-T5b).
//
// The defect this file was written against: the promoted field rendered HINT
// text and nothing else, so its accessible name was the placeholder. The
// `_FieldLabel` a screen draws above it is a separate, unassociated Text node —
// a sighted user sees "Name" over an empty box, a screen-reader user landing on
// the box hears "Maya". That came in verbatim from `account_screen.dart`'s
// private `_InputField`, and thirteen P4b screens take free text.
//
// The fix is one `Semantics(label:)` around the field and a required `label`
// argument, so a screen physically cannot ship an unnamed field.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';

import '../support/harness.dart';

Future<TextEditingController> _pumpField(
  WidgetTester tester, {
  String label = 'Name',
  String hint = 'Maya',
  String text = '',
  bool obscure = false,
  bool enabled = true,
}) async {
  final controller = TextEditingController(text: text);
  addTearDown(controller.dispose);

  await pumpApp(
    tester,
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // How every call site renders it: the visible label ABOVE the field.
          Text(label),
          const SizedBox(height: 6),
          LumenInputField(
            controller: controller,
            label: label,
            hint: hint,
            obscure: obscure,
            enabled: enabled,
          ),
        ],
      ),
    ),
  );
  return controller;
}

SemanticsData _fieldSemantics(WidgetTester tester) =>
    tester.getSemantics(find.byType(TextField)).getSemanticsData();

void main() {
  testWidgetsWithSemantics('an empty field announces its LABEL first, then '
      'the placeholder', (tester) async {
    await _pumpField(tester);

    expectLabeledField(tester, find.byType(TextField), 'Name');
    // Both halves, in order: the placeholder is still useful ("what goes in
    // here"), it just must not BE the name.
    expect(_fieldSemantics(tester).label, 'Name\nMaya');
  });

  testWidgetsWithSemantics('a filled field announces its label with the text '
      'as its value', (tester) async {
    await _pumpField(tester, text: 'Maya S');
    final data = _fieldSemantics(tester);

    expectLabeledField(tester, find.byType(TextField), 'Name');
    expect(data.label, 'Name');
    expect(
      data.value,
      'Maya S',
      reason:
          'The entered text is the field\'s VALUE, not its name — a screen '
          'reader announces "Name, edit box, Maya S".',
    );
  });

  testWidgetsWithSemantics('a disabled field keeps its name', (tester) async {
    // A field greyed out during an in-flight write is exactly where a
    // hint-only name disappears: no text, no focus, nothing to announce.
    await _pumpField(tester, enabled: false);

    expectLabeledField(tester, find.byType(TextField), 'Name');
  });

  testWidgetsWithSemantics('a password field is named and announces as '
      'obscured', (tester) async {
    await _pumpField(
      tester,
      label: 'Password',
      hint: '••••••••',
      text: 'hunter2',
      obscure: true,
    );

    expectLabeledField(tester, find.byType(TextField), 'Password');
    expect(
      _fieldSemantics(tester).flagsCollection.isObscured,
      isTrue,
      reason:
          'An obscured field must announce as obscured, or assistive tech '
          'reads the password out loud.',
    );
  });

  testWidgetsWithSemantics('the field is not announced as a button', (
    tester,
  ) async {
    await _pumpField(tester);

    expectNotAButton(tester, find.byType(TextField));
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpField(tester, hint: 'you@example.com');

    expectNoDingbats(tester, screen: 'LumenInputField');
  });
}
