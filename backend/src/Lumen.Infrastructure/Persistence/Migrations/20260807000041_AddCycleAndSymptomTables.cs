using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Lumen.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddCycleAndSymptomTables : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "cycle_day_logs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Day = table.Column<DateOnly>(type: "date", nullable: false),
                    Pain = table.Column<short>(type: "smallint", nullable: true),
                    Mood = table.Column<short>(type: "smallint", nullable: true),
                    Energy = table.Column<short>(type: "smallint", nullable: true),
                    Libido = table.Column<short>(type: "smallint", nullable: true),
                    NotesEnc = table.Column<byte[]>(type: "bytea", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    DeletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_cycle_day_logs", x => x.Id);
                    table.CheckConstraint("ck_cycle_day_logs_mood_range", "\"Mood\" >= 1 AND \"Mood\" <= 4");
                    table.CheckConstraint("ck_cycle_day_logs_pain_range", "\"Pain\" >= 0 AND \"Pain\" <= 10");
                    table.ForeignKey(
                        name: "FK_cycle_day_logs_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "cycle_events",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    OccurredOn = table.Column<DateOnly>(type: "date", nullable: false),
                    FlowIntensity = table.Column<short>(type: "smallint", nullable: true),
                    NotesEnc = table.Column<byte[]>(type: "bytea", nullable: true),
                    Source = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    DeletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_cycle_events", x => x.Id);
                    table.CheckConstraint("ck_cycle_events_flow_intensity_range", "\"FlowIntensity\" >= 1 AND \"FlowIntensity\" <= 4");
                    table.ForeignKey(
                        name: "FK_cycle_events_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "cycle_phase_overrides",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CycleStartOn = table.Column<DateOnly>(type: "date", nullable: false),
                    Phase = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Boundary = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: false),
                    OccurredOn = table.Column<DateOnly>(type: "date", nullable: false),
                    Source = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    DeletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_cycle_phase_overrides", x => x.Id);
                    table.ForeignKey(
                        name: "FK_cycle_phase_overrides_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "symptoms",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    SymptomCode = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    Intensity = table.Column<short>(type: "smallint", nullable: false),
                    Region = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "unspecified"),
                    Side = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: true),
                    PainTypes = table.Column<List<string>>(type: "text[]", nullable: false),
                    Triggers = table.Column<List<string>>(type: "text[]", nullable: false),
                    OccurredAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    OccurredOn = table.Column<DateOnly>(type: "date", nullable: false),
                    NotesEnc = table.Column<byte[]>(type: "bytea", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    DeletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_symptoms", x => x.Id);
                    table.CheckConstraint("ck_symptoms_intensity_range", "\"Intensity\" >= 0 AND \"Intensity\" <= 10");
                    table.ForeignKey(
                        name: "FK_symptoms_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_cycle_day_logs_UserId_Day",
                table: "cycle_day_logs",
                columns: new[] { "UserId", "Day" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_cycle_events_UserId_Kind_OccurredOn",
                table: "cycle_events",
                columns: new[] { "UserId", "Kind", "OccurredOn" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_cycle_events_UserId_OccurredOn",
                table: "cycle_events",
                columns: new[] { "UserId", "OccurredOn" });

            migrationBuilder.CreateIndex(
                name: "IX_cycle_phase_overrides_UserId_CycleStartOn",
                table: "cycle_phase_overrides",
                columns: new[] { "UserId", "CycleStartOn" });

            migrationBuilder.CreateIndex(
                name: "IX_cycle_phase_overrides_UserId_CycleStartOn_Phase_Boundary",
                table: "cycle_phase_overrides",
                columns: new[] { "UserId", "CycleStartOn", "Phase", "Boundary" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_symptoms_UserId_OccurredOn_OccurredAt",
                table: "symptoms",
                columns: new[] { "UserId", "OccurredOn", "OccurredAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "cycle_day_logs");

            migrationBuilder.DropTable(
                name: "cycle_events");

            migrationBuilder.DropTable(
                name: "cycle_phase_overrides");

            migrationBuilder.DropTable(
                name: "symptoms");
        }
    }
}
