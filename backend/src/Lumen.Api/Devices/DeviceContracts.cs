using Lumen.Domain.Entities;

namespace Lumen.Api.Devices;

// The DTOs of the device-registration feature (§C.9), per the T3 convention
// `<Feature>/<Feature>Contracts.cs`.
//
// On the `namespace` above (§G12, corrected after T4's review): `AddSwaggerGen()` is bare — no
// `CustomSchemaIds` — so the OpenAPI schema id is `type.Name` and is namespace-INDEPENDENT. The real
// hazard is a short-type-name COLLISION across feature folders, which throws a duplicate-schemaId
// error at document generation, so both names below are globally unique: `RegisterDeviceRequest` and
// `RegisterDeviceResponse` appear nowhere else in the tree.
//
// NOTE — no `[DefaultValue]` anywhere in this file, deliberately. T13 shipped one on a NULLABLE member
// and it made the property un-nullable in the generated Dart client forever (openapi-generator's
// dart-dio + built_value output turns a schema `default` into a builder default, and its deserializer
// skips explicit nulls). Both request members here are nullable, and a default on `platform` would
// additionally register every device as one platform without the client ever saying so.

/// <summary>
/// Body of <c>POST /me/devices</c> — push-token registration, called by the client on first launch
/// and on <b>every token refresh for the life of the install</b>.
///
/// <para><b>This is an UPSERT on the existing unique <c>(UserId, PushToken)</c></b>, so re-sending
/// the same token is idempotent: the row's <see cref="Platform"/> and <c>lastSeenAt</c> move, the id
/// does not, and the answer is 200 either way. Both members are required — this is not a PATCH, and
/// there is no "leave unchanged" state for a two-field registration.</para>
///
/// <para><b>Registering a token DETACHES it from every other account</b> (see
/// <see cref="DeviceRegistrationService"/>). Nothing on the wire says so, which is why it is written
/// here as well as there.</para>
/// </summary>
/// <param name="Platform">
/// One of <see cref="UserDevice.Platforms"/> — <c>ios</c> or <c>android</c>. Anything else is a 400:
/// the code decides which provider P9a dispatches through, so an unknown platform is a device that
/// can never be reached, and storing it would hide that until dispatch ships.
/// </param>
/// <param name="PushToken">
/// The FCM/APNs registration token, 1–<see cref="UserDevice.PushTokenMaxLength"/> characters
/// (the existing column's width — <b>not a P4a invention</b>, §G11). Trimmed before it is measured
/// and stored, the same rule <c>notes</c> follows. <b>PII (§F):</b> never logged, never echoed back —
/// there is deliberately no corresponding member on <see cref="RegisterDeviceResponse"/>.
/// </param>
public record RegisterDeviceRequest(
    string? Platform,
    string? PushToken);

/// <summary>
/// The 200 body of <c>POST /me/devices</c>: the stored device row, <b>minus its token</b>.
/// </summary>
/// <remarks>
/// <para><b>Always 200, never 201.</b> An upsert has no actionable created/updated distinction for
/// this caller — the client re-registers on every token refresh and does nothing differently on the
/// first one — and §C.9 exposes no <c>GET /me/devices/{id}</c> for a <c>Location</c> header to point
/// at.</para>
///
/// <para><b>There is no <c>pushToken</c> member and there must never be one.</b> The caller already
/// holds the token; echoing it would put PII into client logs, proxy traces and every HAR file a
/// support ticket carries, for nothing. Pinned by
/// <c>OpenApiContractTests.OpenApi_device_response_never_documents_the_push_token</c> so it cannot be
/// added back without the contract test failing.</para>
/// </remarks>
/// <param name="DeviceId">
/// The row's id — stable across re-registrations of the same token, and the handle a later phase's
/// unregister endpoint (P9a) will address. It identifies a row, not a person, and carries none of the
/// token.
/// </param>
/// <param name="Platform">The stored platform, echoed so the client can confirm what it registered as.</param>
/// <param name="LastSeenAt">
/// The instant this registration landed. Non-nullable here even though the column is nullable: every
/// path through this endpoint stamps it, and the column stays nullable only for rows written before
/// the endpoint existed.
/// </param>
/// <param name="CreatedAt">
/// When the device was FIRST registered. Unchanged by a re-registration, which is what lets a client
/// tell "this install has been known for months" from "this is a new device".
/// </param>
public record RegisterDeviceResponse(
    Guid DeviceId,
    string Platform,
    DateTimeOffset LastSeenAt,
    DateTimeOffset CreatedAt);
