using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddTranscriptionPhase23Fields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "KaraokeGranularity",
                table: "UserTranscriptionPreferences",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "off");

            migrationBuilder.AddColumn<double>(
                name: "ContentDetectionConfidence",
                table: "TranscriptionJobs",
                type: "double precision",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "KaraokeGranularity",
                table: "TranscriptionJobs",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "off");

            migrationBuilder.AddColumn<string>(
                name: "KaraokeModeApplied",
                table: "TranscriptionJobs",
                type: "character varying(16)",
                maxLength: 16,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "KaraokeGranularity",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "ContentDetectionConfidence",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "KaraokeGranularity",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "KaraokeModeApplied",
                table: "TranscriptionJobs");
        }
    }
}
