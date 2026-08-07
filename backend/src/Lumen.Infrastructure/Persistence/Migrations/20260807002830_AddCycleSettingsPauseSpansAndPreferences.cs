using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Lumen.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddCycleSettingsPauseSpansAndPreferences : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "cycle_tracking_pause_spans",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Reason = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    StartedOn = table.Column<DateOnly>(type: "date", nullable: false),
                    EndedOn = table.Column<DateOnly>(type: "date", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_cycle_tracking_pause_spans", x => x.Id);
                    table.ForeignKey(
                        name: "FK_cycle_tracking_pause_spans_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_cycle_settings",
                columns: table => new
                {
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    AvgCycleLengthDays = table.Column<short>(type: "smallint", nullable: false, defaultValue: (short)28),
                    AvgPeriodLengthDays = table.Column<short>(type: "smallint", nullable: true),
                    Regularity = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false, defaultValue: "somewhat"),
                    PhasePredictionEnabled = table.Column<bool>(type: "boolean", nullable: false, defaultValue: true),
                    AutoDetectPeriodStartEnabled = table.Column<bool>(type: "boolean", nullable: false, defaultValue: true),
                    ShowFertilityWindowEnabled = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    TrackingPaused = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    PauseReason = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: true),
                    PausedSince = table.Column<DateOnly>(type: "date", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_cycle_settings", x => x.UserId);
                    table.CheckConstraint("ck_user_cycle_settings_avg_cycle_length_positive", "\"AvgCycleLengthDays\" > 0");
                    table.CheckConstraint("ck_user_cycle_settings_avg_period_length_positive", "\"AvgPeriodLengthDays\" IS NULL OR \"AvgPeriodLengthDays\" > 0");
                    table.ForeignKey(
                        name: "FK_user_cycle_settings_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_goals",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    GoalCode = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    Selected = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_goals", x => x.Id);
                    table.ForeignKey(
                        name: "FK_user_goals_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_hormone_prefs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    HormoneCode = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    Charted = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_hormone_prefs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_user_hormone_prefs_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_notification_prefs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CategoryCode = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    Enabled = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_notification_prefs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_user_notification_prefs_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_cycle_tracking_pause_spans_UserId",
                table: "cycle_tracking_pause_spans",
                column: "UserId",
                unique: true,
                filter: "\"EndedOn\" IS NULL");

            migrationBuilder.CreateIndex(
                name: "IX_cycle_tracking_pause_spans_UserId_StartedOn",
                table: "cycle_tracking_pause_spans",
                columns: new[] { "UserId", "StartedOn" });

            migrationBuilder.CreateIndex(
                name: "IX_user_goals_UserId_GoalCode",
                table: "user_goals",
                columns: new[] { "UserId", "GoalCode" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_user_hormone_prefs_UserId_HormoneCode",
                table: "user_hormone_prefs",
                columns: new[] { "UserId", "HormoneCode" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_user_notification_prefs_UserId_CategoryCode",
                table: "user_notification_prefs",
                columns: new[] { "UserId", "CategoryCode" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "cycle_tracking_pause_spans");

            migrationBuilder.DropTable(
                name: "user_cycle_settings");

            migrationBuilder.DropTable(
                name: "user_goals");

            migrationBuilder.DropTable(
                name: "user_hormone_prefs");

            migrationBuilder.DropTable(
                name: "user_notification_prefs");
        }
    }
}
