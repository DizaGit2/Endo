using System.Text;
using System.Text.Json;
using Lumen.Api.Validation;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.Extensions.DependencyInjection;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Validation;

/// <summary>
/// Freezes the P4a 400 contract (T3). Roughly twenty endpoints and the generated Dart client are
/// built on this shape, so it is pinned here rather than re-asserted per endpoint: the field keys are
/// the camelCase JSON names the client already knows, several messages may accumulate under one key,
/// <c>request</c> is reserved for cross-field errors, and the body's <c>detail</c> is the one string
/// the shipped client falls back to when it renders a validation failure.
///
/// <para>
/// The message constants are asserted as literals. They are wire strings, not internal identifiers —
/// asserting them against themselves would pin nothing.
/// </para>
/// </summary>
public class ValidationProblemBuilderTests
{
    // --- accumulation ------------------------------------------------------

    [Fact]
    public void Two_messages_under_one_key_aggregate_into_one_array()
    {
        var errors = ErrorsOf(new ValidationProblemBuilder()
            .Add("avgCycleLengthDays", ValidationMessages.NotNegative)
            .Add("avgCycleLengthDays", ValidationMessages.Between(10, 120)));

        errors.Keys.ShouldBe(["avgCycleLengthDays"]);
        errors["avgCycleLengthDays"].ShouldBe(
            ["value must be 0 or greater", "value must be between 10 and 120"]);
    }

    [Fact]
    public void Errors_on_different_keys_stay_separate()
    {
        var errors = ErrorsOf(new ValidationProblemBuilder()
            .Add("occurredOn", ValidationMessages.FutureDate)
            .Add("kind", ValidationMessages.NotAllowedValue));

        errors.Count.ShouldBe(2);
        errors["occurredOn"].ShouldBe(["date must not be in the future"]);
        errors["kind"].ShouldBe(["value is not one of the allowed values"]);
    }

    [Fact]
    public void Field_keys_are_passed_through_verbatim_so_camel_case_and_indexes_survive()
    {
        // The client matches these against its own JSON field names; any normalisation here
        // (PascalCase, lowercasing, stripping the index) would silently orphan the message.
        var errors = ErrorsOf(new ValidationProblemBuilder()
            .Add("avgCycleLengthDays", ValidationMessages.Required)
            .Add("boundaries[0].occurredOn", ValidationMessages.BeforeFloor));

        errors.Keys.Order().ShouldBe(["avgCycleLengthDays", "boundaries[0].occurredOn"]);
    }

    [Fact]
    public void AddIf_adds_only_when_the_condition_holds()
    {
        var builder = new ValidationProblemBuilder();
        builder.HasErrors.ShouldBeFalse();

        builder.AddIf(false, "notes", ValidationMessages.MaxLength(2000));
        builder.HasErrors.ShouldBeFalse();

        builder.AddIf(true, "notes", ValidationMessages.MaxLength(2000));
        builder.HasErrors.ShouldBeTrue();
        ErrorsOf(builder)["notes"].ShouldBe(["text exceeds the maximum length of 2000 characters"]);
    }

    // --- the reserved cross-field key --------------------------------------

    [Fact]
    public void The_request_key_is_reserved_for_cross_field_errors()
    {
        ValidationProblemBuilder.RequestKey.ShouldBe("request");

        var errors = ErrorsOf(new ValidationProblemBuilder()
            .AddRequest("at least one of pain, mood or notes is required")
            .AddRequestIf(true, "provide at least one baseline field")
            .AddRequestIf(false, "never added"));

        errors.Keys.ShouldBe(["request"]);
        errors["request"].ShouldBe(
            ["at least one of pain, mood or notes is required", "provide at least one baseline field"]);
    }

    // --- Build() -----------------------------------------------------------

    [Fact]
    public void Build_returns_a_400_validation_problem_carrying_the_shared_detail()
    {
        var result = new ValidationProblemBuilder()
            .Add("timezone", ValidationMessages.NotAnIanaTimeZone)
            .Build();

        var problem = result.ShouldBeOfType<ProblemHttpResult>();
        problem.StatusCode.ShouldBe(StatusCodes.Status400BadRequest);

        var details = problem.ProblemDetails.ShouldBeOfType<HttpValidationProblemDetails>();
        details.Status.ShouldBe(StatusCodes.Status400BadRequest);
        details.Detail.ShouldBe("The request contained invalid data.");
        details.Errors["timezone"].ShouldBe(["value is not a recognized IANA time zone"]);
    }

    [Fact]
    public async Task Build_writes_the_400_envelope_the_client_parses()
    {
        // The whole point of T3 is ONE 400 body. Executed for real (not inspected in memory) so this
        // is directly comparable to ProblemExceptionHandlerTests, which asserts the same envelope for
        // a request that could not be bound at all.
        var (contentType, statusCode, json) = await ExecuteAsync(new ValidationProblemBuilder()
            .Add("occurredOn", ValidationMessages.FutureDate)
            .AddRequest("at least one of pain, mood or notes is required"));

        statusCode.ShouldBe(StatusCodes.Status400BadRequest);
        contentType.ShouldNotBeNull().ShouldStartWith("application/problem+json");

        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        root.GetProperty("status").GetInt32().ShouldBe(StatusCodes.Status400BadRequest);
        // The client reads `detail` first and only falls back to `title`, so this is the sentence a
        // user actually sees for every field-level rejection in the phase.
        root.GetProperty("detail").GetString().ShouldBe("The request contained invalid data.");
        // The framework's HttpValidationProblemDetails default. Pinned rather than left implicit
        // because it is on the wire; it deliberately differs from the handler's "Validation failed."
        // so the two producers stay distinguishable in logs while the parsed shape stays identical.
        root.GetProperty("title").GetString().ShouldBe("One or more validation errors occurred.");

        var errors = root.GetProperty("errors");
        errors.GetProperty("occurredOn").EnumerateArray().Select(e => e.GetString()).ShouldBe(
            ["date must not be in the future"]);
        errors.GetProperty("request").EnumerateArray().Select(e => e.GetString()).ShouldBe(
            ["at least one of pain, mood or notes is required"]);
    }

    [Fact]
    public void Build_with_nothing_accumulated_throws_rather_than_returning_an_empty_400()
    {
        // A 400 with `errors: {}` tells the client nothing and would mean the caller forgot its
        // HasErrors guard. Fail loudly instead of shipping a meaningless rejection.
        Should.Throw<InvalidOperationException>(() => new ValidationProblemBuilder().Build());
    }

    // --- the frozen vocabulary ---------------------------------------------

    [Fact]
    public void Shared_message_constants_are_frozen()
    {
        // RequestDetail is the exact fallback string in client/lib/core/error/error_mapper.dart.
        ValidationMessages.RequestDetail.ShouldBe("The request contained invalid data.");
        ValidationMessages.Required.ShouldBe("value is required");
        ValidationMessages.NotAllowedValue.ShouldBe("value is not one of the allowed values");
        ValidationMessages.NotNegative.ShouldBe("value must be 0 or greater");
        ValidationMessages.FutureDate.ShouldBe("date must not be in the future");
        ValidationMessages.BeforeFloor.ShouldBe("date is before the earliest allowed date");
        ValidationMessages.NotAnIanaTimeZone.ShouldBe("value is not a recognized IANA time zone");
        ValidationMessages.MalformedRequest.ShouldBe("the request body or parameters could not be read");
    }

    [Fact]
    public void Parameterised_messages_are_frozen_at_fixed_arguments()
    {
        ValidationMessages.Between(10, 120).ShouldBe("value must be between 10 and 120");
        ValidationMessages.Between(1, 30).ShouldBe("value must be between 1 and 30");
        ValidationMessages.Between(0, 10).ShouldBe("value must be between 0 and 10");
        ValidationMessages.MaxLength(2000).ShouldBe("text exceeds the maximum length of 2000 characters");
        ValidationMessages.MaxLength(512).ShouldBe("text exceeds the maximum length of 512 characters");
    }

    // --- helpers -----------------------------------------------------------

    private static HttpValidationProblemDetails ProblemOf(ValidationProblemBuilder builder) =>
        builder.Build().ShouldBeOfType<ProblemHttpResult>().ProblemDetails.ShouldBeOfType<HttpValidationProblemDetails>();

    private static IDictionary<string, string[]> ErrorsOf(ValidationProblemBuilder builder) =>
        ProblemOf(builder).Errors;

    private static async Task<(string? ContentType, int StatusCode, string Json)> ExecuteAsync(
        ValidationProblemBuilder builder)
    {
        var services = new ServiceCollection();
        services.AddOptions();
        services.AddLogging();
        services.AddProblemDetails();
        await using var provider = services.BuildServiceProvider();

        var httpContext = new DefaultHttpContext { RequestServices = provider };
        using var responseBody = new MemoryStream();
        httpContext.Response.Body = responseBody;

        await builder.Build().ExecuteAsync(httpContext);

        return (httpContext.Response.ContentType,
            httpContext.Response.StatusCode,
            Encoding.UTF8.GetString(responseBody.ToArray()));
    }
}
