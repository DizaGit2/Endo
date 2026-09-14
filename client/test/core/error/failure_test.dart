// ---------------------------------------------------------------------------
// Failure — the typed-error affordances screens bind to (P4b-T4)
// ---------------------------------------------------------------------------
//
// ValidationFailure.fields was parsed and never read. These tests pin the small
// binding surface a form uses, in particular the INDEXED key form: screen 12
// posts a batch of up to 37 symptom rows, and `entries[3].intensity` must land
// on row 3 and nowhere else.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/error/failure.dart';

void main() {
  // The backend's 400 envelope, key-for-key (survey/backend-endpoints.md §5).
  const failure = ValidationFailure(
    message: 'The request contained invalid data.',
    detail: 'The request contained invalid data.',
    fields: {
      'occurredOn': ['date must not be in the future'],
      'entries[3].intensity': ['value must be between 0 and 10'],
      'painTypes[1]': ['value is not one of the allowed values'],
      'request': ['at least one of pain, mood or notes is required'],
    },
  );

  // -------------------------------------------------------------------------
  // Plain keys
  // -------------------------------------------------------------------------

  group('ValidationFailure — plain field binding', () {
    test('messageFor returns the first message for a known field', () {
      expect(failure.messageFor('occurredOn'), 'date must not be in the future');
    });

    test('messagesFor returns every message for a known field', () {
      const many = ValidationFailure(
        fields: {
          'displayName': ['value is required', 'value is too long'],
        },
      );
      expect(many.messagesFor('displayName'), [
        'value is required',
        'value is too long',
      ]);
      expect(many.messageFor('displayName'), 'value is required');
    });

    test('an unknown field binds to nothing rather than throwing', () {
      expect(failure.messageFor('notAField'), isNull);
      expect(failure.messagesFor('notAField'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Indexed keys — the reason a top-level string is not enough
  // -------------------------------------------------------------------------

  group('ValidationFailure — indexed field binding', () {
    test('path() builds the collection[i].field form the server sends', () {
      expect(ValidationFailure.path('entries', 3, 'intensity'), 'entries[3].intensity');
      expect(ValidationFailure.path('boundaries', 0, 'occurredOn'), 'boundaries[0].occurredOn');
    });

    test('path() builds the element form when there is no sub-field', () {
      expect(ValidationFailure.path('painTypes', 1), 'painTypes[1]');
    });

    test('path() composes into the NESTED form the symptom batch emits', () {
      // SymptomResult.cs:20 / SymptomService.cs:576 emit
      // `entries[0].painTypes[1]`. Without this, T20 hand-rolls the string.
      const nested = 'entries[0].painTypes[1]';
      expect(
        ValidationFailure.path(
          'entries',
          0,
          ValidationFailure.path('painTypes', 1),
        ),
        nested,
      );

      const f = ValidationFailure(
        fields: {
          nested: ['value is not one of the allowed values'],
        },
      );
      expect(f.messageFor(nested), 'value is not one of the allowed values');
      // …and it still belongs to row 0 alone.
      expect(
        f.messageFor(
          ValidationFailure.path(
            'entries',
            1,
            ValidationFailure.path('painTypes', 1),
          ),
        ),
        isNull,
      );
    });

    test('an indexed key binds to its row', () {
      expect(
        failure.messageFor(ValidationFailure.path('entries', 3, 'intensity')),
        'value must be between 0 and 10',
      );
      expect(
        failure.messageFor(ValidationFailure.path('painTypes', 1)),
        'value is not one of the allowed values',
      );
    });

    test('a NEIGHBOURING row does not inherit the error', () {
      // The discriminating case: any "does the key mention intensity?" style
      // lookup would light up every row in the batch.
      expect(failure.messageFor(ValidationFailure.path('entries', 2, 'intensity')), isNull);
      expect(failure.messageFor(ValidationFailure.path('entries', 4, 'intensity')), isNull);
      expect(failure.messageFor(ValidationFailure.path('entries', 30, 'intensity')), isNull);
    });

    test('a different field on the SAME row does not inherit the error', () {
      expect(failure.messageFor(ValidationFailure.path('entries', 3, 'symptomCode')), isNull);
    });

    test('the un-indexed collection name binds to nothing', () {
      expect(failure.messageFor('entries'), isNull);
      expect(failure.messageFor('intensity'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // The reserved `request` key
  // -------------------------------------------------------------------------

  group('ValidationFailure — the reserved `request` key', () {
    test('names no input, so it is exposed separately', () {
      expect(ValidationFailure.requestKey, 'request');
      expect(failure.requestMessages, [
        'at least one of pain, mood or notes is required',
      ]);
    });

    test('is empty when the server sent no cross-field error', () {
      const f = ValidationFailure(fields: {'occurredOn': ['value is required']});
      expect(f.requestMessages, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // ConflictFailure extensions
  // -------------------------------------------------------------------------

  group('ConflictFailure — problem-details extensions', () {
    test('defaults carry no code and no missing steps', () {
      const f = ConflictFailure();
      expect(f.code, isNull);
      expect(f.missingSteps, isEmpty);
      expect(f.message, 'That request conflicts with existing data.');
    });

    test('carries a code and the missing onboarding steps when given', () {
      const f = ConflictFailure(
        message: 'Onboarding cannot be completed until every mandatory step is answered.',
        code: 'onboarding_incomplete',
        missingSteps: ['cycle', 'baseline'],
      );
      expect(f.code, 'onboarding_incomplete');
      expect(f.missingSteps, ['cycle', 'baseline']);
    });
  });
}
