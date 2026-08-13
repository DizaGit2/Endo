using System.Reflection;
using System.Text.RegularExpressions;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Architecture;

/// <summary>
/// Two phase-wide facts that no type-level or behavioural test can express, because both are claims
/// about <b>how many places in <c>backend/src</c> do a thing</b> rather than about what any one of them
/// does. Each was written in T18, and each guards a rule an ordinary green suite would let drift.
///
/// <para><b>1. §G8 — the backdate floor has exactly TWO enforcements, for the rest of the phase.</b>
/// D-13 gives <c>UserDayInfo.BackdateFloor</c> to <c>cycle_events</c> alone: <c>POST /cycle/events</c>
/// (T9) and <c>POST /onboarding/cycle</c> (T18). Applying it to a symptom, a day log, a body metric or
/// a date of birth would reject the historical logging D-13 explicitly permits — and it would do so
/// silently, on data a user has every right to enter. Four files already carry a <i>comment</i> saying
/// they deliberately do not read the floor; the risk this test addresses is the fifth author who copies
/// the wrong pair of lines out of <see cref="Lumen.Api.Cycle.CycleService"/>.</para>
///
/// <para><b>2. <c>POST /onboarding/complete</c> is the only writer of
/// <c>users.OnboardingCompletedAt</c>.</b> The column is the D-02 state machine's terminal state and
/// <c>GET /me.onboardingCompleted</c> is derived from it, so a second writer anywhere would make
/// "onboarded" mean two different things — and would bypass the guarded claim that stamps it exactly
/// once under concurrency. Reads are unrestricted and deliberately so; only assignment is fenced.</para>
///
/// <para><b>Why a source scan.</b> Neither fact is observable through reflection: both are about the
/// <i>absence</i> of code. Comment lines are excluded so the four "there is deliberately no floor here"
/// remarks stay legal, and <c>Migrations</c>/<c>obj</c>/<c>bin</c> are excluded because generated code
/// names every column and is not hand-authored.</para>
/// </summary>
public class BackdateFloorAndCompletionStampTests
{
    /// <summary>Repo-relative paths, forward-slashed so the assertion message reads the same on any OS.</summary>
    private static IReadOnlyList<(string Path, string Line)> ProductionCodeLines()
    {
        var root = Path.Combine(RepoRoot(), "backend", "src");

        return
        [
            .. Directory.EnumerateFiles(root, "*.cs", SearchOption.AllDirectories)
                .Where(IsHandWritten)
                .SelectMany(file => File.ReadAllLines(file)
                    .Where(line => !IsComment(line))
                    .Select(line => (Path: Relative(root, file), Line: line))),
        ];
    }

    private static bool IsHandWritten(string file)
    {
        var normalised = file.Replace('\\', '/');
        return !normalised.Contains("/obj/", StringComparison.Ordinal)
               && !normalised.Contains("/bin/", StringComparison.Ordinal)
               && !normalised.Contains("/Migrations/", StringComparison.Ordinal);
    }

    /// <summary>
    /// A whole-line comment. Trailing comments on a code line are deliberately NOT stripped: a line that
    /// carries real code is scanned whatever follows it.
    /// </summary>
    private static bool IsComment(string line)
    {
        var trimmed = line.TrimStart();
        return trimmed.StartsWith("//", StringComparison.Ordinal)
               || trimmed.StartsWith("/*", StringComparison.Ordinal)
               || trimmed.StartsWith('*');
    }

    private static string Relative(string root, string file) =>
        Path.GetRelativePath(root, file).Replace('\\', '/');

    [Fact]
    public void The_backdate_floor_is_read_by_exactly_two_production_writes()
    {
        // `.BackdateFloor` with the dot, so the record's own declaration and the named argument that
        // computes it in UserDayContext are not counted — those are the definition, not an enforcement.
        var enforcements = ProductionCodeLines()
            .Where(l => l.Line.Contains(".BackdateFloor", StringComparison.Ordinal))
            .ToList();

        enforcements.Select(l => l.Path).Order(StringComparer.Ordinal).ShouldBe(
            ["Lumen.Api/Cycle/CycleService.cs", "Lumen.Api/Onboarding/OnboardingStepsService.cs"],
            Case.Sensitive,
            "§G8: the floor is cycle_events-only — POST /cycle/events (T9) and POST /onboarding/cycle "
            + "(T18) are the ONLY two writes that may read it. Found: "
            + string.Join(" | ", enforcements.Select(l => $"{l.Path}: {l.Line.Trim()}")));

        enforcements.Count.ShouldBe(
            2, "one comparison each; a second read inside either file would be a duplicated rule");
    }

    [Fact]
    public void Users_OnboardingCompletedAt_is_written_in_exactly_one_place()
    {
        var lines = ProductionCodeLines()
            .Where(l => l.Line.Contains("OnboardingCompletedAt", StringComparison.Ordinal))
            .ToList();

        // Every file that so much as names the column, so a new reader is noticed too — reads are fine,
        // but a reader that later grows an assignment should show up in a diff on this test.
        lines.Select(l => l.Path).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ShouldBe(
            [
                "Lumen.Api/Onboarding/OnboardingStepsService.cs",
                "Lumen.Api/Program.cs",
                "Lumen.Domain/Entities/User.cs",
            ],
            Case.Sensitive);

        var writes = lines.Where(l => IsWrite(l.Line)).ToList();

        writes.Select(l => l.Path).ShouldBe(
            ["Lumen.Api/Onboarding/OnboardingStepsService.cs"],
            Case.Sensitive,
            "POST /onboarding/complete is the only writer of users.OnboardingCompletedAt. Found: "
            + string.Join(" | ", writes.Select(l => $"{l.Path}: {l.Line.Trim()}")));

        writes.Count.ShouldBe(
            1,
            "and it writes it once, through the guarded claim — a second assignment would bypass the "
            + "WHERE OnboardingCompletedAt IS NULL predicate that makes concurrent completions stamp once");
    }

    /// <summary>
    /// An assignment, not a comparison: <c>x.OnboardingCompletedAt = …</c> (never <c>==</c>) or the
    /// <c>ExecuteUpdateAsync</c> setter spelling.
    /// </summary>
    private static bool IsWrite(string line) =>
        Regex.IsMatch(line, @"\.OnboardingCompletedAt\s*=(?!=)")
        || Regex.IsMatch(line, @"SetProperty\(\s*\w+\s*=>\s*\w+\.OnboardingCompletedAt\s*,");

    /// <summary>Walks up from the test assembly directory until it finds the repo root (the dir with .git).</summary>
    private static string RepoRoot()
    {
        var dir = new DirectoryInfo(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)!);

        while (dir is not null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, ".git")) ||
                File.Exists(Path.Combine(dir.FullName, ".git")))
            {
                return dir.FullName;
            }

            dir = dir.Parent;
        }

        throw new InvalidOperationException(
            "Could not locate the repo root (no .git found walking up from the test assembly).");
    }
}
