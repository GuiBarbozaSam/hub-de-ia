using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddUserTranscriptionPreferenceVNextFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "AiChunkChars",
                table: "UserTranscriptionPreferences",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "AiEnhancementEnabled",
                table: "UserTranscriptionPreferences",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<int>(
                name: "AiFrameSampleSeconds",
                table: "UserTranscriptionPreferences",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "AiMaxTokens",
                table: "UserTranscriptionPreferences",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AiMode",
                table: "UserTranscriptionPreferences",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "AiModel",
                table: "UserTranscriptionPreferences",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "AiPrompt",
                table: "UserTranscriptionPreferences",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AiProvider",
                table: "UserTranscriptionPreferences",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<double>(
                name: "AiTemperature",
                table: "UserTranscriptionPreferences",
                type: "double precision",
                nullable: true);

            migrationBuilder.AddColumn<double>(
                name: "AiTopP",
                table: "UserTranscriptionPreferences",
                type: "double precision",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "AiUseVisualContext",
                table: "UserTranscriptionPreferences",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<DateTime>(
                name: "CreatedAtUtc",
                table: "UserTranscriptionPreferences",
                type: "timestamp with time zone",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            migrationBuilder.AddColumn<string>(
                name: "DeliveryMode",
                table: "UserTranscriptionPreferences",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<bool>(
                name: "PreserveTimestamps",
                table: "UserTranscriptionPreferences",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "RequestedOutputsJson",
                table: "UserTranscriptionPreferences",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "TargetLanguagesJson",
                table: "UserTranscriptionPreferences",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "VideoDeliveryMode",
                table: "UserTranscriptionPreferences",
                type: "text",
                nullable: false,
                defaultValue: "");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AiChunkChars",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AiEnhancementEnabled",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AiFrameSampleSeconds",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AiMaxTokens",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AiMode",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AiModel",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AiPrompt",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AiProvider",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AiTemperature",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AiTopP",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "AiUseVisualContext",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "CreatedAtUtc",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "DeliveryMode",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "PreserveTimestamps",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "RequestedOutputsJson",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "TargetLanguagesJson",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "VideoDeliveryMode",
                table: "UserTranscriptionPreferences");
        }
    }
}
