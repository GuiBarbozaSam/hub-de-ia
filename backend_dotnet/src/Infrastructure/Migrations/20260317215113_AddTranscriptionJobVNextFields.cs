using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddTranscriptionJobVNextFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "AiChunkChars",
                table: "TranscriptionJobs",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "AiEnhancementEnabled",
                table: "TranscriptionJobs",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<int>(
                name: "AiFrameSampleSeconds",
                table: "TranscriptionJobs",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "AiMaxTokens",
                table: "TranscriptionJobs",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AiMode",
                table: "TranscriptionJobs",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "AiModel",
                table: "TranscriptionJobs",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "AiPrompt",
                table: "TranscriptionJobs",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AiProvider",
                table: "TranscriptionJobs",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<double>(
                name: "AiTemperature",
                table: "TranscriptionJobs",
                type: "double precision",
                nullable: true);

            migrationBuilder.AddColumn<double>(
                name: "AiTopP",
                table: "TranscriptionJobs",
                type: "double precision",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "AiUseVisualContext",
                table: "TranscriptionJobs",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "DeliveryMode",
                table: "TranscriptionJobs",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<bool>(
                name: "PreserveTimestamps",
                table: "TranscriptionJobs",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "RequestedOutputsJson",
                table: "TranscriptionJobs",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "TargetLanguagesJson",
                table: "TranscriptionJobs",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "VideoDeliveryMode",
                table: "TranscriptionJobs",
                type: "text",
                nullable: false,
                defaultValue: "");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AiChunkChars",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "AiEnhancementEnabled",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "AiFrameSampleSeconds",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "AiMaxTokens",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "AiMode",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "AiModel",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "AiPrompt",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "AiProvider",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "AiTemperature",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "AiTopP",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "AiUseVisualContext",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "DeliveryMode",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "PreserveTimestamps",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "RequestedOutputsJson",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "TargetLanguagesJson",
                table: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "VideoDeliveryMode",
                table: "TranscriptionJobs");
        }
    }
}
