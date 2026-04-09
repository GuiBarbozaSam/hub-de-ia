using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddTranscriptionPhase1Fields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AnimeSongLayoutMode",
                table: "UserTranscriptionPreferences",
                type: "character varying(48)",
                maxLength: 48,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "ContentMode",
                table: "UserTranscriptionPreferences",
                type: "character varying(24)",
                maxLength: 24,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "RenderedPreviewMode",
                table: "UserTranscriptionPreferences",
                type: "character varying(24)",
                maxLength: 24,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "SpeakerStyleMode",
                table: "UserTranscriptionPreferences",
                type: "character varying(24)",
                maxLength: 24,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "StyleIntensity",
                table: "UserTranscriptionPreferences",
                type: "character varying(24)",
                maxLength: 24,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "AnimeSongLayoutMode",
                table: "TranscriptionJobs",
                type: "character varying(48)",
                maxLength: 48,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "ContentMode",
                table: "TranscriptionJobs",
                type: "character varying(24)",
                maxLength: 24,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "DetectedContentType",
                table: "TranscriptionJobs",
                type: "character varying(24)",
                maxLength: 24,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "RenderedPreviewMode",
                table: "TranscriptionJobs",
                type: "character varying(24)",
                maxLength: 24,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "SpeakerModeApplied",
                table: "TranscriptionJobs",
                type: "character varying(24)",
                maxLength: 24,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SpeakerStyleMode",
                table: "TranscriptionJobs",
                type: "character varying(24)",
                maxLength: 24,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "StyleIntensity",
                table: "TranscriptionJobs",
                type: "character varying(24)",
                maxLength: 24,
                nullable: false,
                defaultValue: "");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AnimeSongLayoutMode",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "ContentMode",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "RenderedPreviewMode",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "SpeakerStyleMode",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "StyleIntensity",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AnimeSongLayoutMode",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "ContentMode",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "DetectedContentType",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "RenderedPreviewMode",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "SpeakerModeApplied",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "SpeakerStyleMode",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "StyleIntensity",
                table: "TranscriptionJobs");
        }
    }
}
