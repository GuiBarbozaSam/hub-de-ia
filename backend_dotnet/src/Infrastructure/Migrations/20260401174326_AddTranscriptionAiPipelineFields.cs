using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddTranscriptionAiPipelineFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "AiRevisionPasses",
                table: "UserTranscriptionPreferences",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "ContextHintsJson",
                table: "UserTranscriptionPreferences",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "EnableOnlineContext",
                table: "UserTranscriptionPreferences",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "QualityProfile",
                table: "UserTranscriptionPreferences",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "UseAdvancedAlignment",
                table: "UserTranscriptionPreferences",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<int>(
                name: "AiRevisionPasses",
                table: "TranscriptionJobs",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "CapabilityProfileJson",
                table: "TranscriptionJobs",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ContextHintsJson",
                table: "TranscriptionJobs",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "CurrentPass",
                table: "TranscriptionJobs",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "CurrentStage",
                table: "TranscriptionJobs",
                type: "character varying(32)",
                maxLength: 32,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<bool>(
                name: "EnableOnlineContext",
                table: "TranscriptionJobs",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "QualityProfile",
                table: "TranscriptionJobs",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "QualitySummaryJson",
                table: "TranscriptionJobs",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "StyleSource",
                table: "TranscriptionJobs",
                type: "character varying(32)",
                maxLength: 32,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "TotalPasses",
                table: "TranscriptionJobs",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "TranslationStatusesJson",
                table: "TranscriptionJobs",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "UseAdvancedAlignment",
                table: "TranscriptionJobs",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AiRevisionPasses",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "ContextHintsJson",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "EnableOnlineContext",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "QualityProfile",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "UseAdvancedAlignment",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AiRevisionPasses",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "CapabilityProfileJson",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "ContextHintsJson",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "CurrentPass",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "CurrentStage",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "EnableOnlineContext",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "QualityProfile",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "QualitySummaryJson",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "StyleSource",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "TotalPasses",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "TranslationStatusesJson",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "UseAdvancedAlignment",
                table: "TranscriptionJobs");
        }
    }
}
