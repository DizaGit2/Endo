using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Lumen.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddAdminAuditLogEntityIndex : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_admin_audit_log_EntityId_Action",
                table: "admin_audit_log",
                columns: new[] { "EntityId", "Action" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_admin_audit_log_EntityId_Action",
                table: "admin_audit_log");
        }
    }
}
