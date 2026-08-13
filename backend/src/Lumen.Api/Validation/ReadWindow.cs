namespace Lumen.Api.Validation;

/// <summary>
/// The inclusive day-span ceiling shared by every windowed read: <c>GET /cycle/calendar</c> (T13) and
/// <c>GET /symptoms</c> (T12, capped in the T12 defect-fix commit that hoisted this constant here).
/// <b>A P4a INVENTION (§G11)</b>, recorded here and in the T22 STATUS block so a later phase does not
/// mistake 366 for a ratified clinical or product number: it bounds a query, and it means nothing else.
/// </summary>
/// <remarks>
/// <para><b>Why this exists at all.</b> T13 shipped the cap only on <c>GET /cycle/calendar</c>; T12's
/// <c>GET /symptoms</c> paged its rows (D-13's 50/100 offset page) but never bounded the WINDOW those
/// rows are counted over — <c>matching.CountAsync(ct)</c> ran an unbounded <c>COUNT(*)</c> for whatever
/// <c>from</c>/<c>to</c> the caller supplied, so <c>?from=1900-01-01&amp;to=2100-01-01</c> was a
/// full-table count per request on an authenticated endpoint. The page cap does not bound that at all.
/// Hoisted here, out of <c>Cycle.CycleCalendarWindow</c>, when <c>GET /symptoms</c> became the second
/// windowed read to need the same ceiling — the same rule that hoisted
/// <see cref="FieldLimits.MaxNotesLength"/> and <see cref="ValidationMessages.RangeEndBeforeStart"/>:
/// one number stated by one decision must not exist in two places.</para>
///
/// <para><b>This is a bounded DATE WINDOW, not the D-13 50/100 offset page</b> — the reading matters,
/// because it is why neither windowed read's <c>limit</c>/<c>offset</c> (where one exists) has anything
/// to do with this cap. A cap on the window is a cap on the query it drives, independent of how the
/// result is paged.</para>
///
/// <para>366 rather than 365 so a leap year's complete calendar still fits in one request. The cap is
/// inclusive and both ends of the window count toward it, so the widest legal window is
/// <c>from + 365</c>.</para>
/// </remarks>
public static class ReadWindow
{
    /// <summary>The inclusive ceiling in days: a 366-day window is accepted, a 367-day one is a 400.</summary>
    public const int MaxDays = 366;
}
