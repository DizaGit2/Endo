using System.Globalization;
using System.Text;
using Lumen.Api.CycleSettings;
using Lumen.Api.Devices;
using Lumen.Api.Onboarding;
using Lumen.Api.Validation;
using Lumen.Domain.Entities;
using Lumen.UnitTests.Cycle;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Onboarding;

/// <summary>
/// Unit tests for <see cref="OnboardingStepsService"/>'s baseline step (T16) — the D-02 screen-4
/// write that lands three <b>encrypted</b> profile columns plus <c>rasrm_stage_enc</c> and
/// <c>diagnosed_on_enc</c>, and seeds <b>one</b> <c>body_metrics.weight_kg</c> row (rider 4: weight has
/// one source of truth), and the <c>GET /me</c> read path that makes all of it reachable.
///
/// <para>Sqlite in-memory over the real model, plus <see cref="TestUserCryptoContext"/> — the real
/// <c>AesGcmFieldCipher</c> over a fixed 32-byte DEK, deliberately not a pass-through fake, because
/// "is this column really ciphertext" is one of the claims this file has to make.</para>
///
/// <para><b>What Sqlite cannot prove here</b> is the <c>body_metrics</c> FILTERED unique index
/// (§G9's one deliberate tombstone exception). The code path is proven here; the constraint is proven
/// against real Postgres in <c>OnboardingBaselineLiveTests</c>.</para>
/// </summary>
public sealed class OnboardingBaselineTests : IDisposable
{
    private readonly CycleTestHarness _harness = new();

    public void Dispose() => _harness.Dispose();

    /// <summary>Screen 4's four answers plus the two rider-4 condition fields, all supplied.</summary>
    private static SaveBaselineRequest Full(
        DateOnly? dob = null,
        int? heightCm = 165,
        decimal? weightKg = 60.4m,
        string? endoStatus = UserProfileEnc.EndoStatuses.Diagnosed,
        int? rasrmStage = 3,
        string? diagnosedOn = "2023-08") =>
        new(dob ?? new DateOnly(1994, 3, 17), heightCm, weightKg, endoStatus, rasrmStage, diagnosedOn);

    private static SaveBaselineRequest Empty() => new(null, null, null, null, null, null);

    private static IReadOnlyList<OnboardingFieldError> ErrorsOf(SaveBaselineResult result) =>
        result.ShouldBeOfType<SaveBaselineResult.Invalid>().Errors;

    private static IReadOnlyList<string> KeysOf(SaveBaselineResult result) =>
        [.. ErrorsOf(result).Select(e => e.Field)];

    private static string MessageFor(SaveBaselineResult result, string field) =>
        ErrorsOf(result).Single(e => string.Equals(e.Field, field, StringComparison.Ordinal)).Message;

    private static BaselineResponse SavedOf(SaveBaselineResult result) =>
        result.ShouldBeOfType<SaveBaselineResult.Saved>().Baseline;

    // ---------------------------------------------------------------- the frozen wire strings (§G12)

    [Fact]
    public void The_baseline_wire_strings_are_frozen()
    {
        // These reach the Flutter client through the OpenAPI contract and are rendered verbatim, so a
        // reword is a contract change, not a copy edit. Asserted against the literal, never against
        // the constant, or the test would move with the code it is meant to pin.
        OnboardingValidationMessages.BaselineEmpty.ShouldBe("provide at least one baseline field");
        OnboardingValidationMessages.WeightOutOfRange(BaselineStructuralDomain.MaxWeightKg)
            .ShouldBe("value must be greater than 0 and at most 9999.9");
        OnboardingValidationMessages.WeightTooPrecise.ShouldBe("value must have at most 1 decimal place");
        BaselineStructuralDomain.MaxWeightDecimals.ShouldBe(
            1, "the message states the precision in the singular; a 2 here would make it ungrammatical and wrong");
        OnboardingValidationMessages.NotAMonth.ShouldBe("value must be a month in the form yyyy-MM");

        // The three shared messages this endpoint reuses rather than restating (T3/§G12).
        ValidationMessages.FutureDate.ShouldBe("date must not be in the future");
        ValidationMessages.NotAllowedValue.ShouldBe("value is not one of the allowed values");
        ValidationMessages.Between(1, 4).ShouldBe("value must be between 1 and 4");
        ValidationMessages.Between(
            BaselineStructuralDomain.MinHeightCm,
            BaselineStructuralDomain.MaxHeightCm).ShouldBe("value must be between 1 and 32767");
    }

    // ---------------------------------------------------------------- the empty body

    [Fact]
    public async Task A_body_carrying_no_baseline_field_at_all_is_rejected_under_the_request_key()
    {
        // D-02 makes this step SKIPPABLE, and "skip" means not calling the endpoint. A no-op POST is a
        // client bug, and answering 200 would let it ship.
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(Empty(), default);

        KeysOf(result).ShouldBe([ValidationProblemBuilder.RequestKey]);
        MessageFor(result, ValidationProblemBuilder.RequestKey).ShouldBe(OnboardingValidationMessages.BaselineEmpty);
    }

    [Fact]
    public async Task A_blank_string_field_counts_as_absent_not_as_a_value()
    {
        // Same rule PATCH /me and POST /me/devices follow: whitespace is not an answer.
        var result = await _harness.NewOnboardingStepsService()
            .SaveBaselineAsync(new SaveBaselineRequest(null, null, null, "   ", null, "  "), default);

        KeysOf(result).ShouldBe([ValidationProblemBuilder.RequestKey]);
    }

    // ---------------------------------------------------------------- dob (§G8: today, and nothing else)

    [Fact]
    public async Task A_dob_after_the_users_local_today_is_rejected()
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(CycleTestHarness.Today.AddDays(1), null, null, null, null, null), default);

        MessageFor(result, "dob").ShouldBe(ValidationMessages.FutureDate);
    }

    [Fact]
    public async Task A_dob_of_today_itself_is_accepted()
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(CycleTestHarness.Today, null, null, null, null, null), default);

        SavedOf(result).Dob.ShouldBe(CycleTestHarness.Today);
    }

    [Fact]
    public async Task A_dob_decades_before_the_account_was_created_is_accepted()
    {
        // §G8: the backdate floor is `cycle_events`-ONLY. `UserDayInfo.BackdateFloor` here is account
        // creation − 2 y (2024-08-06), and every real user's DOB is decades before that — applying the
        // floor to this field would make the endpoint unusable for its actual purpose.
        var dob = new DateOnly(1961, 11, 2);
        dob.ShouldBeLessThan(CycleTestHarness.Floor, "the arrangement is only meaningful below the floor");

        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(dob, null, null, null, null, null), default);

        SavedOf(result).Dob.ShouldBe(dob);
    }

    // ---------------------------------------------------------------- heightCm

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(BaselineStructuralDomain.MaxHeightCm + 1)]
    public async Task A_height_outside_the_structural_domain_is_rejected(int heightCm)
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, heightCm, null, null, null, null), default);

        MessageFor(result, "heightCm").ShouldBe(ValidationMessages.Between(
            BaselineStructuralDomain.MinHeightCm, BaselineStructuralDomain.MaxHeightCm));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(140)]
    [InlineData(165)]
    [InlineData(210)]
    [InlineData(272)]                                     // the tallest human ever recorded
    [InlineData(BaselineStructuralDomain.MaxHeightCm)]
    public async Task Every_height_a_person_could_have_is_stored_rather_than_refused(int heightCm)
    {
        // The guard is STRUCTURAL (§G7/§G11): it refuses what cannot be a measurement at all, never a
        // measurement a clinician would raise an eyebrow at. No clinical bound lives in backend/src.
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, heightCm, null, null, null, null), default);

        SavedOf(result).HeightCm.ShouldBe(heightCm);
    }

    // ---------------------------------------------------------------- weightKg

    [Fact]
    public async Task A_weight_with_more_than_one_decimal_place_is_rejected()
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, 60.44m, null, null, null), default);

        MessageFor(result, "weightKg").ShouldBe(OnboardingValidationMessages.WeightTooPrecise);
    }

    [Fact]
    public async Task A_weight_with_exactly_one_decimal_place_is_accepted()
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, 60.4m, null, null, null), default);

        SavedOf(result).LatestWeightKg.ShouldBe(60.4m);
    }

    [Theory]
    [InlineData("0")]
    [InlineData("-1")]
    [InlineData("-60.4")]
    [InlineData("10000")]
    public async Task A_weight_outside_the_structural_domain_is_rejected(string weightKg)
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(
                null, null, decimal.Parse(weightKg, CultureInfo.InvariantCulture), null, null, null), default);

        MessageFor(result, "weightKg").ShouldBe(
            OnboardingValidationMessages.WeightOutOfRange(BaselineStructuralDomain.MaxWeightKg));
    }

    [Theory]
    [InlineData("0.1")]
    [InlineData("38")]
    [InlineData("60.4")]
    [InlineData("120.5")]
    [InlineData("635")]                                   // the heaviest human ever recorded
    [InlineData("9999.9")]
    public async Task Every_weight_a_scale_could_report_is_stored_rather_than_refused(string weightKg)
    {
        var value = decimal.Parse(weightKg, CultureInfo.InvariantCulture);

        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, value, null, null, null), default);

        SavedOf(result).LatestWeightKg.ShouldBe(value);
    }

    [Fact]
    public async Task A_trailing_zero_weight_is_normalised_into_the_canonical_plaintext()
    {
        // JSON `60.40` binds to a decimal of SCALE 2, and `decimal.ToString()` preserves scale — so
        // without normalisation the column would hold "60.40" while an identical later save held
        // "60.4". Same number, two canonical forms, and BodyMetric.EncodeValue is supposed to have
        // exactly one.
        var service = _harness.NewOnboardingStepsService();
        var result = await service.SaveBaselineAsync(
            new SaveBaselineRequest(null, null, 60.40m, null, null, null), default);

        SavedOf(result).LatestWeightKg.ShouldBe(60.4m);

        await using var db = _harness.NewContext();
        var row = await db.BodyMetrics.AsNoTracking().SingleAsync(m => m.UserId == _harness.UserId);
        (await _harness.Crypto.DecryptStringAsync(row.ValueEnc)).ShouldBe("60.4");
    }

    // ---------------------------------------------------------------- endoStatus

    [Fact]
    public async Task The_endo_status_vocabulary_is_matched_case_sensitively()
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, null, "Diagnosed", null, null), default);

        MessageFor(result, "endoStatus").ShouldBe(ValidationMessages.NotAllowedValue);
    }

    [Fact]
    public async Task Every_ratified_endo_status_code_is_accepted()
    {
        UserProfileEnc.EndoStatuses.All.Count.ShouldBe(3, "the ratified set is three members (§G10)");

        foreach (var code in UserProfileEnc.EndoStatuses.All)
        {
            var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
                new SaveBaselineRequest(null, null, null, code, null, null), default);

            SavedOf(result).EndoStatus.ShouldBe(code);
        }
    }

    // ---------------------------------------------------------------- rasrmStage (this writer IS the check)

    [Theory]
    [InlineData(0)]
    [InlineData(5)]
    [InlineData(-1)]
    [InlineData(int.MaxValue)]
    public async Task A_rasrm_stage_outside_one_to_four_is_rejected(int stage)
    {
        // The column is CIPHERTEXT, so the 1–4 range cannot be a DB CHECK (§D / the XML doc on
        // UserProfileEnc.RasrmStageEnc). THIS writer is the only thing enforcing it: delete the guard
        // and a stage of 9 is stored with nothing anywhere failing.
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, null, null, stage, null), default);

        MessageFor(result, "rasrmStage").ShouldBe(ValidationMessages.Between(
            UserProfileEnc.RasrmStages.Min, UserProfileEnc.RasrmStages.Max));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(4)]
    public async Task Every_rasrm_stage_in_range_round_trips_as_the_invariant_culture_digit(int stage)
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, null, null, stage, null), default);

        SavedOf(result).RasrmStage.ShouldBe(stage);

        await using var db = _harness.NewContext();
        var profile = await db.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == _harness.UserId);
        (await _harness.Crypto.DecryptStringAsync(profile.RasrmStageEnc!))
            .ShouldBe(stage.ToString(CultureInfo.InvariantCulture));
    }

    [Fact]
    public async Task A_null_rasrm_stage_is_accepted_because_a_diagnosed_user_often_does_not_know_it()
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, null, UserProfileEnc.EndoStatuses.Diagnosed, null, null), default);

        SavedOf(result).RasrmStage.ShouldBeNull();

        await using var db = _harness.NewContext();
        var profile = await db.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == _harness.UserId);
        profile.RasrmStageEnc.ShouldBeNull("the stage is independent of the status; it stays absent");
    }

    [Fact]
    public void The_rasrm_stage_encoder_is_culture_independent_and_rejects_anything_but_a_bare_digit()
    {
        var previous = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo("ar-SA"); // eastern-arabic digit shapes
            UserProfileEnc.RasrmStages.Encode(3).ShouldBe("3");
            UserProfileEnc.RasrmStages.Decode("3").ShouldBe(3);
        }
        finally
        {
            CultureInfo.CurrentCulture = previous;
        }

        Should.Throw<ArgumentOutOfRangeException>(() => UserProfileEnc.RasrmStages.Encode(5));
        Should.Throw<FormatException>(() => UserProfileEnc.RasrmStages.Decode("+3"));
        Should.Throw<FormatException>(() => UserProfileEnc.RasrmStages.Decode("3.0"));
    }

    // ---------------------------------------------------------------- diagnosedOn (yyyy-MM, never a day)

    [Theory]
    [InlineData("2023-13")]      // month 13
    [InlineData("2023-00")]      // month 0
    [InlineData("2023-8")]       // unpadded
    [InlineData("08-2023")]      // transposed
    [InlineData("2023")]         // year only
    [InlineData("2023-08-15")]   // a full DATE — the coercion this field must never accept
    [InlineData("not-a-month")]
    public async Task A_diagnosis_month_that_is_not_yyyy_MM_is_rejected(string diagnosedOn)
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, null, null, null, diagnosedOn), default);

        MessageFor(result, "diagnosedOn").ShouldBe(OnboardingValidationMessages.NotAMonth);
    }

    [Fact]
    public async Task A_diagnosis_month_after_the_users_current_month_is_rejected()
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, null, null, null, "2026-09"), default);

        MessageFor(result, "diagnosedOn").ShouldBe(ValidationMessages.FutureDate);
    }

    [Fact]
    public async Task The_users_current_month_is_accepted_even_though_it_has_not_ended()
    {
        // Today is 2026-08-06: a diagnosis received this month is not "in the future".
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, null, null, null, "2026-08"), default);

        SavedOf(result).DiagnosedOn.ShouldBe("2026-08");
    }

    [Fact]
    public async Task A_diagnosis_month_is_stored_as_a_month_and_can_never_be_read_back_as_a_day()
    {
        var service = _harness.NewOnboardingStepsService();
        await service.SaveBaselineAsync(
            new SaveBaselineRequest(null, null, null, null, null, "2023-08"), default);

        await using var db = _harness.NewContext();
        var profile = await db.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == _harness.UserId);
        var plaintext = await _harness.Crypto.DecryptStringAsync(profile.DiagnosedOnEnc!);

        plaintext.ShouldBe("2023-08", "the canonical plaintext is month precision — never a fabricated day");
        plaintext.Length.ShouldBe(7);

        // The decoder is the other half of the guarantee: a "yyyy-MM-dd" value in this column is a hard
        // error, so a future writer cannot quietly widen the field to a full date.
        Should.Throw<FormatException>(() => UserProfileEnc.DecodeDiagnosedOn("2023-08-15"));
        UserProfileEnc.DecodeDiagnosedOn("2023-08").ShouldBe(new DateOnly(2023, 8, 1));
    }

    // ---------------------------------------------------------------- validate-then-act

    [Fact]
    public async Task Every_bad_field_is_reported_in_one_response_and_nothing_is_written()
    {
        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(
                CycleTestHarness.Today.AddDays(1), 0, 60.44m, "Diagnosed", 9, "2023-13"), default);

        KeysOf(result).OrderBy(k => k, StringComparer.Ordinal).ShouldBe(
            ["diagnosedOn", "dob", "endoStatus", "heightCm", "rasrmStage", "weightKg"],
            Case.Sensitive,
            "validate-then-act: a form with six bad fields must not take six round trips to fix");

        await using var db = _harness.NewContext();
        (await db.UserProfiles.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(0);
        (await db.BodyMetrics.CountAsync(m => m.UserId == _harness.UserId)).ShouldBe(0);
    }

    // ---------------------------------------------------------------- the 404 fence

    [Fact]
    public async Task A_crypto_shredded_user_gets_404_before_validation_and_writes_nothing()
    {
        // The fence that makes an erased account's still-valid JWT inert. Checked BEFORE validation, so
        // a body that would otherwise be a 400 still answers "no such user" and leaks nothing about the
        // shape the server understood.
        var result = await _harness.NewOnboardingStepsService(info: null)
            .SaveBaselineAsync(Full(heightCm: 0, weightKg: -1m, endoStatus: "Diagnosed"), default);

        result.ShouldBeOfType<SaveBaselineResult.UserNotFound>();

        await using var db = _harness.NewContext();
        (await db.UserProfiles.CountAsync()).ShouldBe(0);
        (await db.BodyMetrics.CountAsync()).ShouldBe(0);
    }

    // ---------------------------------------------------------------- ciphertext at rest

    // AES-GCM blob framing per AesGcmFieldCipher: nonce(12) ‖ ciphertext(n) ‖ tag(16). The nonce and
    // tag are random bytes, not derived from the plaintext, so any single byte value has a 1/256
    // chance of turning up at any of their 28 positions "by accident" — nothing to do with whether
    // the field is really encrypted.
    private const int GcmNonceSize = 12;
    private const int GcmTagSize = 16;

    // Below this many plaintext UTF-8 bytes, a substring search across the 28 random nonce+tag bytes
    // has a non-negligible chance of a false hit (a single byte: ~10.7%; two or more: well under
    // 0.1%). Only RasrmStageEnc's "3" is this short today — see task-16 review fix.
    private const int MinPlaintextBytesForSubstringCheck = 2;

    [Fact]
    public async Task Every_encrypted_column_this_step_writes_holds_ciphertext_at_rest()
    {
        await _harness.NewOnboardingStepsService().SaveBaselineAsync(Full(), default);

        await using var db = _harness.NewContext();
        var profile = await db.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == _harness.UserId);
        var metric = await db.BodyMetrics.AsNoTracking().SingleAsync(m => m.UserId == _harness.UserId);

        var columns = new (string Name, byte[] Bytes, string Plaintext)[]
        {
            ("DobEnc", profile.DobEnc!, "1994-03-17"),
            ("HeightCmEnc", profile.HeightCmEnc!, "165"),
            ("EndoStatusEnc", profile.EndoStatusEnc!, "diagnosed"),
            ("RasrmStageEnc", profile.RasrmStageEnc!, "3"),
            ("DiagnosedOnEnc", profile.DiagnosedOnEnc!, "2023-08"),
            ("ValueEnc", metric.ValueEnc, "60.4"),
        };

        foreach (var (name, bytes, plaintext) in columns)
        {
            bytes.ShouldNotBeNull(name);
            var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);

            // Framing: the blob is exactly nonce + ciphertext-the-same-length-as-the-plaintext + tag.
            // Deterministic, and it would catch a regression that stored the plaintext alongside (or
            // instead of) the ciphertext, which a pure length check on its own would not.
            bytes.Length.ShouldBe(
                GcmNonceSize + plaintextBytes.Length + GcmTagSize,
                $"{name} must be framed as a {GcmNonceSize}-byte nonce + ciphertext + {GcmTagSize}-byte tag");

            bytes.ShouldNotBe(plaintextBytes, name);

            // The substring claim only carries information when a chance byte match in the random
            // nonce/tag is negligible. For a one-character plaintext it is not (~10.7%, measured at
            // 2/16 in the review that flagged this test as flaky) — the framing, byte-inequality and
            // decrypt-round-trip assertions above and below already prove opacity for that case
            // without gambling on 28 random bytes.
            if (plaintextBytes.Length >= MinPlaintextBytesForSubstringCheck)
            {
                Encoding.UTF8.GetString(bytes).ShouldNotContain(
                    plaintext, Case.Sensitive, $"{name} must be AES-GCM ciphertext, never the plaintext");
            }

            // And it is real, reversible ciphertext rather than an opaque blob nobody can read back.
            (await _harness.Crypto.DecryptStringAsync(bytes)).ShouldBe(plaintext, name);
        }
    }

    [Fact]
    public async Task Re_posting_the_same_answers_rotates_every_ciphertext()
    {
        // AES-GCM uses a fresh nonce per encryption, so identical plaintext must never produce
        // identical bytes: equal ciphertexts across two saves would mean the nonce is being reused,
        // which is the one catastrophic misuse of GCM.
        var service = _harness.NewOnboardingStepsService();
        await service.SaveBaselineAsync(Full(), default);

        byte[] firstProfileBytes;
        byte[] firstMetricBytes;
        await using (var read = _harness.NewContext())
        {
            firstProfileBytes = (await read.UserProfiles.AsNoTracking()
                .SingleAsync(p => p.UserId == _harness.UserId)).HeightCmEnc!;
            firstMetricBytes = (await read.BodyMetrics.AsNoTracking()
                .SingleAsync(m => m.UserId == _harness.UserId)).ValueEnc;
        }

        await _harness.NewOnboardingStepsService().SaveBaselineAsync(Full(), default);

        await using var db = _harness.NewContext();
        var profile = await db.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == _harness.UserId);
        var metric = await db.BodyMetrics.AsNoTracking().SingleAsync(m => m.UserId == _harness.UserId);

        profile.HeightCmEnc.ShouldNotBe(firstProfileBytes, "a re-save must rotate the nonce");
        metric.ValueEnc.ShouldNotBe(firstMetricBytes, "a re-save must rotate the nonce");
        (await _harness.Crypto.DecryptStringAsync(profile.HeightCmEnc!)).ShouldBe("165");
        (await _harness.Crypto.DecryptStringAsync(metric.ValueEnc)).ShouldBe("60.4");
    }

    // ---------------------------------------------------------------- merge semantics

    [Fact]
    public async Task A_null_field_leaves_the_stored_value_intact()
    {
        // `null` means "leave unchanged", exactly like PATCH /me — it is never a reset. D-02 makes this
        // a step the user revisits, and screen 31 edits one field at a time.
        await _harness.NewOnboardingStepsService().SaveBaselineAsync(Full(), default);

        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, 170, null, null, null, null), default);

        var saved = SavedOf(result);
        saved.HeightCm.ShouldBe(170, "the supplied field moved");
        saved.Dob.ShouldBe(new DateOnly(1994, 3, 17));
        saved.EndoStatus.ShouldBe(UserProfileEnc.EndoStatuses.Diagnosed);
        saved.RasrmStage.ShouldBe(3);
        saved.DiagnosedOn.ShouldBe("2023-08");
        saved.LatestWeightKg.ShouldBe(60.4m, "an omitted weight must not delete the metric row");

        await using var db = _harness.NewContext();
        (await db.BodyMetrics.CountAsync(m => m.UserId == _harness.UserId)).ShouldBe(1);
    }

    [Fact]
    public async Task The_profile_row_is_created_when_the_user_has_none()
    {
        await using (var arrange = _harness.NewContext())
            (await arrange.UserProfiles.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(0);

        await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, 165, null, null, null, null), default);

        await using var db = _harness.NewContext();
        var profile = await db.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == _harness.UserId);
        profile.CreatedAt.ShouldBe(CycleTestHarness.Now);
        profile.UpdatedAt.ShouldBe(CycleTestHarness.Now);
    }

    // ---------------------------------------------------------------- the weight seed (§G9 FILTERED)

    [Fact]
    public async Task The_weight_seeds_exactly_one_metric_row_and_a_same_day_re_post_keeps_the_count_at_one()
    {
        // Rider 4: weight has ONE source of truth. D-02 makes the step re-submittable, and a client that
        // double-taps "Continue" must not stack a second row on the same user-local day.
        await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, 60.4m, null, null, null), default);
        await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, 61.2m, null, null, null), default);

        await using var db = _harness.NewContext();
        var rows = await db.BodyMetrics.AsNoTracking().Where(m => m.UserId == _harness.UserId).ToListAsync();

        rows.Count.ShouldBe(1, "an upsert on (UserId, weight_kg, user-local day), never an append");
        rows[0].Metric.ShouldBe(BodyMetric.Metrics.WeightKg);
        rows[0].Source.ShouldBe(BodyMetric.Sources.Manual);
        rows[0].MeasuredOn.ShouldBe(CycleTestHarness.Today, "the day key is the USER's day (D-12)");
        (await _harness.Crypto.DecryptStringAsync(rows[0].ValueEnc)).ShouldBe("61.2");
    }

    [Fact]
    public async Task A_weight_logged_on_a_later_day_is_a_second_row_not_an_overwrite()
    {
        await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, 60.4m, null, null, null), default);

        var tomorrow = CycleTestHarness.Today.AddDays(1);
        await _harness.NewOnboardingStepsService(_harness.DayInfo(now: CycleTestHarness.Now.AddDays(1), today: tomorrow))
            .SaveBaselineAsync(new SaveBaselineRequest(null, null, 61.2m, null, null, null), default);

        await using var db = _harness.NewContext();
        var rows = await db.BodyMetrics.AsNoTracking()
            .Where(m => m.UserId == _harness.UserId).OrderBy(m => m.MeasuredOn).ToListAsync();

        rows.Count.ShouldBe(2, "body_metrics is a time series keyed by day — P5 charts it");
        rows[0].MeasuredOn.ShouldBe(CycleTestHarness.Today);
        rows[1].MeasuredOn.ShouldBe(tomorrow);
    }

    [Fact]
    public async Task The_baseline_stays_re_submittable_after_the_weight_row_is_soft_deleted()
    {
        // §G9's ONE deliberate FILTERED-index exception exists precisely for this. Under an unfiltered
        // index the tombstone would keep occupying (UserId, weight_kg, today) and this re-submit would
        // fail with a constraint violation on a row the user believes they deleted. So the lookup here
        // deliberately does NOT use IgnoreQueryFilters(): a tombstone is not revived, a NEW row is
        // inserted alongside it.
        await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, 60.4m, null, null, null), default);

        Guid tombstonedId;
        await using (var delete = _harness.NewContext())
        {
            var row = await delete.BodyMetrics.SingleAsync(m => m.UserId == _harness.UserId);
            tombstonedId = row.Id;
            row.DeletedAt = CycleTestHarness.Now;
            await delete.SaveChangesAsync();
        }

        var result = await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, 62.5m, null, null, null), default);

        SavedOf(result).LatestWeightKg.ShouldBe(62.5m);

        await using var db = _harness.NewContext();
        var live = await db.BodyMetrics.AsNoTracking().SingleAsync(m => m.UserId == _harness.UserId);
        live.Id.ShouldNotBe(tombstonedId, "the tombstone is NOT revived — the filtered index frees the key");
        (await _harness.Crypto.DecryptStringAsync(live.ValueEnc)).ShouldBe("62.5");

        (await db.BodyMetrics.IgnoreQueryFilters().CountAsync(m => m.UserId == _harness.UserId))
            .ShouldBe(2, "the tombstone survives the re-submit, invisible to every read");
    }

    // ---------------------------------------------------------------- idempotency of the whole step

    [Fact]
    public async Task Re_submitting_the_identical_baseline_is_idempotent()
    {
        var first = SavedOf(await _harness.NewOnboardingStepsService().SaveBaselineAsync(Full(), default));
        var second = SavedOf(await _harness.NewOnboardingStepsService().SaveBaselineAsync(Full(), default));

        second.ShouldBe(first, "the step is skippable and revisitable — re-posting must converge, not accumulate");

        await using var db = _harness.NewContext();
        (await db.UserProfiles.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(1);
        (await db.BodyMetrics.CountAsync(m => m.UserId == _harness.UserId)).ShouldBe(1);
    }

    // ---------------------------------------------------------------- tenant isolation

    [Fact]
    public async Task One_users_baseline_is_invisible_to_and_untouched_by_another()
    {
        await _harness.NewOnboardingStepsService().SaveBaselineAsync(Full(), default);

        await _harness.NewOnboardingStepsService(_harness.DayInfo(userId: _harness.OtherUserId))
            .SaveBaselineAsync(Full(heightCm: 180, weightKg: 88.1m, endoStatus: UserProfileEnc.EndoStatuses.Suspected,
                rasrmStage: 1, diagnosedOn: "2019-02"), default);

        var mine = await _harness.NewOnboardingStepsService().ReadBaselineAsync(_harness.UserId, default);
        mine.HeightCm.ShouldBe(165);
        mine.LatestWeightKg.ShouldBe(60.4m);
        mine.EndoStatus.ShouldBe(UserProfileEnc.EndoStatuses.Diagnosed);
        mine.RasrmStage.ShouldBe(3);

        var theirs = await _harness.NewOnboardingStepsService().ReadBaselineAsync(_harness.OtherUserId, default);
        theirs.HeightCm.ShouldBe(180);
        theirs.LatestWeightKg.ShouldBe(88.1m);
    }

    // ---------------------------------------------------------------- the read path (GET /me)

    [Fact]
    public async Task The_read_path_is_all_nulls_before_anything_has_been_written()
    {
        // Otherwise a brand-new account would render screen 31 with fabricated values.
        var baseline = await _harness.NewOnboardingStepsService().ReadBaselineAsync(_harness.UserId, default);

        baseline.Dob.ShouldBeNull();
        baseline.HeightCm.ShouldBeNull();
        baseline.EndoStatus.ShouldBeNull();
        baseline.RasrmStage.ShouldBeNull();
        baseline.DiagnosedOn.ShouldBeNull();
        baseline.LatestWeightKg.ShouldBeNull();
    }

    [Fact]
    public async Task The_read_path_decrypts_all_five_condition_fields_and_the_latest_live_weight()
    {
        // Without this every column T7 added would be write-only for the rest of the phase, and the
        // already-shipped screen 31 would have nothing to render.
        await _harness.NewOnboardingStepsService().SaveBaselineAsync(Full(), default);

        var tomorrow = CycleTestHarness.Today.AddDays(1);
        await _harness.NewOnboardingStepsService(_harness.DayInfo(now: CycleTestHarness.Now.AddDays(1), today: tomorrow))
            .SaveBaselineAsync(new SaveBaselineRequest(null, null, 59.8m, null, null, null), default);

        var baseline = await _harness.NewOnboardingStepsService().ReadBaselineAsync(_harness.UserId, default);

        baseline.Dob.ShouldBe(new DateOnly(1994, 3, 17));
        baseline.HeightCm.ShouldBe(165);
        baseline.EndoStatus.ShouldBe(UserProfileEnc.EndoStatuses.Diagnosed);
        baseline.RasrmStage.ShouldBe(3);
        baseline.DiagnosedOn.ShouldBe("2023-08");
        baseline.LatestWeightKg.ShouldBe(59.8m, "the LATEST measured day wins, not the first");
    }

    [Fact]
    public async Task The_read_path_ignores_a_soft_deleted_weight_row_and_falls_back_to_the_previous_day()
    {
        await _harness.NewOnboardingStepsService().SaveBaselineAsync(
            new SaveBaselineRequest(null, null, 60.4m, null, null, null), default);

        var tomorrow = CycleTestHarness.Today.AddDays(1);
        await _harness.NewOnboardingStepsService(_harness.DayInfo(now: CycleTestHarness.Now.AddDays(1), today: tomorrow))
            .SaveBaselineAsync(new SaveBaselineRequest(null, null, 59.8m, null, null, null), default);

        await using (var delete = _harness.NewContext())
        {
            var latest = await delete.BodyMetrics.SingleAsync(m => m.UserId == _harness.UserId && m.MeasuredOn == tomorrow);
            latest.DeletedAt = CycleTestHarness.Now.AddDays(1);
            await delete.SaveChangesAsync();
        }

        var baseline = await _harness.NewOnboardingStepsService().ReadBaselineAsync(_harness.UserId, default);
        baseline.LatestWeightKg.ShouldBe(60.4m, "a tombstoned entry is not the user's current weight");
    }

    [Fact]
    public async Task The_saved_response_is_the_same_projection_the_read_path_returns()
    {
        // The 200 body decrypts back out of the stored row rather than echoing the request, so a
        // round-trip failure is visible immediately instead of at the next GET /me.
        var saved = SavedOf(await _harness.NewOnboardingStepsService().SaveBaselineAsync(Full(), default));
        var read = await _harness.NewOnboardingStepsService().ReadBaselineAsync(_harness.UserId, default);

        saved.ShouldBe(read);
    }

    // ---------------------------------------------------------------- the unit-of-work decision (§G12)

    [Fact]
    public async Task SaveBaselineAsync_OWNS_the_whole_unit_of_work_and_leaves_nothing_staged()
    {
        // The composability decision for T16, stated as a test rather than a comment: NO later task
        // composes this step (T17 owns notifications, T18 owns cycle + state), so the service keeps its
        // own single ConcurrencyRetry action — the two 23505 hazards are real (the user_profile_enc PK
        // on a first save, and the body_metrics filtered unique key on a double-tapped Continue).
        await using var db = _harness.NewContext();
        var dayContext = new StubUserDayContext(_harness.DayInfo());
        var service = new OnboardingStepsService(
            db,
            dayContext,
            _harness.Crypto,
            new DeviceRegistrationService(db, dayContext),
            new CycleSettingsService(db, dayContext));

        await service.SaveBaselineAsync(Full(), default);

        // Nothing is left UNSAVED. (Saved entities stay tracked as `Unchanged` — that is EF's identity
        // map, not pending work — so the claim is about pending states, not about the map being empty.)
        db.ChangeTracker.Entries()
            .Where(e => e.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
            .ShouldBeEmpty("the method saves everything it stages, in one unit of work");

        await using var read = _harness.NewContext();
        (await read.UserProfiles.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(1);
        (await read.BodyMetrics.CountAsync(m => m.UserId == _harness.UserId)).ShouldBe(1);
    }

    [Fact]
    public async Task SaveBaselineAsync_is_NOT_composable_because_its_retry_clears_the_whole_change_tracker()
    {
        // The mirror image of T14's `ApplyOnboardingCycleAsync_STAGES_ONLY_…` guard. §G12's hazard is
        // that `ConcurrencyRetry` recovers via `ChangeTracker.Clear()`, a WHOLE-CONTEXT operation on the
        // request-scoped LumenDbContext — so a caller that staged work first loses it silently. T15
        // documents that about `RegisterAsync` but never tested it; this pins it, so a later task that
        // tries to compose the baseline step fails here instead of shipping a lost onboarding answer.
        await using var db = _harness.NewContext();
        var dayContext = new StubUserDayContext(_harness.DayInfo());
        var service = new OnboardingStepsService(
            db,
            dayContext,
            _harness.Crypto,
            new DeviceRegistrationService(db, dayContext),
            new CycleSettingsService(db, dayContext));

        var stagedElsewhere = new CycleEvent
        {
            Id = Guid.NewGuid(),
            UserId = _harness.UserId,
            Kind = CycleEvent.Kinds.PeriodStart,
            OccurredOn = CycleTestHarness.Today.AddDays(-3),
            Source = CycleEvent.Sources.Onboarding,
            CreatedAt = CycleTestHarness.Now,
            UpdatedAt = CycleTestHarness.Now,
        };
        db.CycleEvents.Add(stagedElsewhere);

        await service.SaveBaselineAsync(Full(), default);

        db.Entry(stagedElsewhere).State.ShouldBe(
            EntityState.Detached,
            "SaveBaselineAsync owns the unit of work and clears the tracker — a caller must never stage " +
            "work before invoking it. A future task that needs to compose this step must first split out " +
            "a stage-only method, the way T14 and T15 did.");

        await using var read = _harness.NewContext();
        (await read.CycleEvents.CountAsync(e => e.UserId == _harness.UserId)).ShouldBe(0);
        (await read.UserProfiles.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(1);
    }
}
