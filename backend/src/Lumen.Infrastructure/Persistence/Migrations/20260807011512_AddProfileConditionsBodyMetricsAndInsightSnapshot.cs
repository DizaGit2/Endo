using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Lumen.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddProfileConditionsBodyMetricsAndInsightSnapshot : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "UnitSystem",
                table: "users",
                type: "character varying(8)",
                maxLength: 8,
                nullable: false,
                defaultValue: "metric");

            migrationBuilder.AddColumn<byte[]>(
                name: "DiagnosedOnEnc",
                table: "user_profile_enc",
                type: "bytea",
                nullable: true);

            migrationBuilder.AddColumn<byte[]>(
                name: "EndoStatusEnc",
                table: "user_profile_enc",
                type: "bytea",
                nullable: true);

            migrationBuilder.AddColumn<byte[]>(
                name: "HeightCmEnc",
                table: "user_profile_enc",
                type: "bytea",
                nullable: true);

            migrationBuilder.AddColumn<byte[]>(
                name: "RasrmStageEnc",
                table: "user_profile_enc",
                type: "bytea",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "body_metrics",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Metric = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
                    ValueEnc = table.Column<byte[]>(type: "bytea", nullable: false),
                    Source = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false, defaultValue: "manual"),
                    MeasuredAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    MeasuredOn = table.Column<DateOnly>(type: "date", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    DeletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_body_metrics", x => x.Id);
                    table.ForeignKey(
                        name: "FK_body_metrics_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_insight_snapshot",
                columns: table => new
                {
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CurrentPhase = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: true),
                    PhaseStart = table.Column<DateOnly>(type: "date", nullable: true),
                    DataCompleteness = table.Column<short>(type: "smallint", nullable: true),
                    MissingDataCardsEnc = table.Column<byte[]>(type: "bytea", nullable: true),
                    ComputedBy = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false, defaultValue: "placeholder"),
                    RefreshedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_insight_snapshot", x => x.UserId);
                    table.CheckConstraint("ck_user_insight_snapshot_data_completeness_range", "\"DataCompleteness\" >= 0 AND \"DataCompleteness\" <= 100");
                    table.ForeignKey(
                        name: "FK_user_insight_snapshot_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_body_metrics_UserId_Metric_MeasuredOn",
                table: "body_metrics",
                columns: new[] { "UserId", "Metric", "MeasuredOn" },
                unique: true,
                filter: "\"DeletedAt\" IS NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "body_metrics");

            migrationBuilder.DropTable(
                name: "user_insight_snapshot");

            migrationBuilder.DropColumn(
                name: "UnitSystem",
                table: "users");

            migrationBuilder.DropColumn(
                name: "DiagnosedOnEnc",
                table: "user_profile_enc");

            migrationBuilder.DropColumn(
                name: "EndoStatusEnc",
                table: "user_profile_enc");

            migrationBuilder.DropColumn(
                name: "HeightCmEnc",
                table: "user_profile_enc");

            migrationBuilder.DropColumn(
                name: "RasrmStageEnc",
                table: "user_profile_enc");
        }
    }
}
