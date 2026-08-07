using System.Globalization;
using Lumen.Domain.Entities;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Body;

/// <summary>
/// <c>body_metrics.ValueEnc</c> holds AES-GCM ciphertext of a <b>string</b>, so the plaintext
/// encoding is the value's only contract. If it were culture-sensitive, a Spanish or German
/// request thread would write "60,4" and an English one would read it back as a
/// <see cref="FormatException"/> — or, far worse, "60.4" written under <c>en-US</c> would parse
/// under <c>de-DE</c> as <b>604 kg</b> with no error at all. These tests pin the one canonical
/// encoder (<see cref="BodyMetric.EncodeValue"/> / <see cref="BodyMetric.DecodeValue"/>) as
/// invariant-culture in both directions.
/// </summary>
public class WeightEncodingTests
{
    /// <summary>The onboarding baseline weight from screen 4 — one decimal place.</summary>
    private const decimal Weight = 60.4m;

    private static void UnderCulture(string culture, Action assert)
    {
        var previousCulture = CultureInfo.CurrentCulture;
        var previousUiCulture = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo(culture);
            CultureInfo.CurrentUICulture = new CultureInfo(culture);
            assert();
        }
        finally
        {
            CultureInfo.CurrentCulture = previousCulture;
            CultureInfo.CurrentUICulture = previousUiCulture;
        }
    }

    [Theory]
    [InlineData("es-ES")]
    [InlineData("de-DE")]
    [InlineData("en-US")]
    public void Weight_round_trips_through_the_canonical_encoder(string culture) =>
        UnderCulture(culture, () => BodyMetric.DecodeValue(BodyMetric.EncodeValue(Weight)).ShouldBe(Weight));

    [Theory]
    [InlineData("es-ES")]
    [InlineData("de-DE")]
    [InlineData("en-US")]
    public void Encoding_always_writes_a_dot_decimal_separator(string culture) =>
        UnderCulture(culture, () => BodyMetric.EncodeValue(Weight).ShouldBe("60.4"));

    [Theory]
    [InlineData("es-ES")]
    [InlineData("de-DE")]
    [InlineData("en-US")]
    public void Decoding_always_reads_a_dot_decimal_separator(string culture) =>
        UnderCulture(culture, () => BodyMetric.DecodeValue("60.4").ShouldBe(Weight));

    [Theory]
    [InlineData("es-ES")]
    [InlineData("de-DE")]
    [InlineData("en-US")]
    public void A_comma_decimal_string_is_rejected_rather_than_silently_misread(string culture) =>
        // NumberStyles.Float excludes AllowThousands, so the invariant thousands separator cannot
        // turn "60,4" into 604 either. A locale-formatted string is a hard error, never a wrong kg.
        UnderCulture(culture, () => Should.Throw<FormatException>(() => BodyMetric.DecodeValue("60,4")));

    [Fact]
    public void The_regression_this_encoder_prevents_is_real()
    {
        // Documented counter-example, asserted so it cannot rot: the naive culture-sensitive parse
        // of the very same canonical string reads 60.4 kg as 604 kg under de-DE, because "." is a
        // thousands separator there and NumberStyles.Number allows it. No exception, no signal.
        decimal.Parse("60.4", CultureInfo.GetCultureInfo("de-DE")).ShouldBe(604m);
        BodyMetric.DecodeValue("60.4").ShouldBe(60.4m);
    }

    [Theory]
    [InlineData("0.1")]
    [InlineData("1")]
    [InlineData("60.4")]
    [InlineData("72.55")]
    [InlineData("120.0")]
    [InlineData("999.999")]
    public void Every_plausible_weight_survives_a_decode_encode_round_trip(string canonical) =>
        UnderCulture("de-DE", () =>
            BodyMetric.EncodeValue(BodyMetric.DecodeValue(canonical)).ShouldBe(canonical));

    [Fact]
    public void The_encoder_is_the_same_for_every_metric_not_just_weight() =>
        // Metrics is a one-member set today (D-15 is open, P5 owns the rest), but the encoder is a
        // property of the value column, not of weight — P5 adds members without a second encoder.
        UnderCulture("es-ES", () => BodyMetric.EncodeValue(87.5m).ShouldBe("87.5"));
}
