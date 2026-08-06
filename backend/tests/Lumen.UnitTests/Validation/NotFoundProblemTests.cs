using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.HttpResults;
using Lumen.Api.Validation;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Validation;

/// <summary>
/// Pins <see cref="NotFoundProblem"/> (T3 review fix): the 404 body T3's brief specified only as a
/// commit-message convention — <c>TypedResults.Problem(statusCode: 404, title: "The requested
/// resource was not found.")</c> — hand-copied into fifteen later tasks with nothing to catch a typo.
/// This test is what now catches it.
/// </summary>
public class NotFoundProblemTests
{
    [Fact]
    public void Result_is_a_404_problem_with_the_frozen_title()
    {
        var result = NotFoundProblem.Result();

        var problem = result.ShouldBeOfType<ProblemHttpResult>();
        problem.StatusCode.ShouldBe(StatusCodes.Status404NotFound);
        problem.ProblemDetails.Status.ShouldBe(StatusCodes.Status404NotFound);
        // Literal, not NotFoundProblem.Title — asserting a constant against itself would pin nothing.
        problem.ProblemDetails.Title.ShouldBe("The requested resource was not found.");
    }

    [Fact]
    public void Title_constant_is_the_frozen_wire_string()
    {
        // So callers/tests elsewhere can assert the literal verbatim without retyping it.
        NotFoundProblem.Title.ShouldBe("The requested resource was not found.");
    }
}
