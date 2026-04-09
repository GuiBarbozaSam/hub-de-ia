using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddTranscriptionJobsAndPreferences : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "Language",
                table: "UserTranscriptionPreferences",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "character varying(16)",
                oldMaxLength: 16,
                oldNullable: true);

            migrationBuilder.AddColumn<int>(
                name: "BeamSize",
                table: "UserTranscriptionPreferences",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<bool>(
                name: "BurnSubtitlesIntoVideo",
                table: "UserTranscriptionPreferences",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "ComputeType",
                table: "UserTranscriptionPreferences",
                type: "character varying(32)",
                maxLength: 32,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "DevicePreference",
                table: "UserTranscriptionPreferences",
                type: "character varying(32)",
                maxLength: 32,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<bool>(
                name: "GenerateSubtitles",
                table: "UserTranscriptionPreferences",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "KeepTimestamps",
                table: "UserTranscriptionPreferences",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<int>(
                name: "MaxSubtitleChars",
                table: "UserTranscriptionPreferences",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "OutputFormat",
                table: "UserTranscriptionPreferences",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "SourceTypeDefault",
                table: "UserTranscriptionPreferences",
                type: "character varying(32)",
                maxLength: 32,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<bool>(
                name: "SplitBySentence",
                table: "UserTranscriptionPreferences",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "SubtitleStyle",
                table: "UserTranscriptionPreferences",
                type: "character varying(64)",
                maxLength: 64,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<bool>(
                name: "VadFilter",
                table: "UserTranscriptionPreferences",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "WordTimestamps",
                table: "UserTranscriptionPreferences",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.CreateTable(
                name: "TranscriptionJobs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<string>(type: "text", nullable: false),
                    SourceType = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    SourceValue = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: false),
                    Model = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    Task = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    Language = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    OutputFormat = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    GenerateSubtitles = table.Column<bool>(type: "boolean", nullable: false),
                    BurnSubtitlesIntoVideo = table.Column<bool>(type: "boolean", nullable: false),
                    KeepTimestamps = table.Column<bool>(type: "boolean", nullable: false),
                    SplitBySentence = table.Column<bool>(type: "boolean", nullable: false),
                    WordTimestamps = table.Column<bool>(type: "boolean", nullable: false),
                    VadFilter = table.Column<bool>(type: "boolean", nullable: false),
                    DevicePreference = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    ComputeType = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    BeamSize = table.Column<int>(type: "integer", nullable: false),
                    MaxSubtitleChars = table.Column<int>(type: "integer", nullable: true),
                    SubtitleStyle = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    Status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    ProgressPercent = table.Column<int>(type: "integer", nullable: false),
                    ErrorMessage = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    LanguageDetected = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: true),
                    DurationSeconds = table.Column<double>(type: "double precision", nullable: true),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    StartedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    FinishedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TranscriptionJobs", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "TranscriptionJobOutputs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    JobId = table.Column<Guid>(type: "uuid", nullable: false),
                    OutputType = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    ContentText = table.Column<string>(type: "text", nullable: true),
                    FilePath = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TranscriptionJobOutputs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_TranscriptionJobOutputs_TranscriptionJobs_JobId",
                        column: x => x.JobId,
                        principalTable: "TranscriptionJobs",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_TranscriptionJobOutputs_JobId",
                table: "TranscriptionJobOutputs",
                column: "JobId");

            migrationBuilder.CreateIndex(
                name: "IX_TranscriptionJobOutputs_OutputType",
                table: "TranscriptionJobOutputs",
                column: "OutputType");

            migrationBuilder.CreateIndex(
                name: "IX_TranscriptionJobs_CreatedAtUtc",
                table: "TranscriptionJobs",
                column: "CreatedAtUtc");

            migrationBuilder.CreateIndex(
                name: "IX_TranscriptionJobs_Status",
                table: "TranscriptionJobs",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_TranscriptionJobs_UserId",
                table: "TranscriptionJobs",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "TranscriptionJobOutputs");

            migrationBuilder.DropTable(
                name: "TranscriptionJobs");

            migrationBuilder.DropColumn(
                name: "BeamSize",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "BurnSubtitlesIntoVideo",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "ComputeType",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "DevicePreference",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "GenerateSubtitles",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "KeepTimestamps",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "MaxSubtitleChars",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "OutputFormat",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "SourceTypeDefault",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "SplitBySentence",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "SubtitleStyle",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "VadFilter",
                table: "UserTranscriptionPreferences");

            migrationBuilder.DropColumn(
                name: "WordTimestamps",
                table: "UserTranscriptionPreferences");

            migrationBuilder.AlterColumn<string>(
                name: "Language",
                table: "UserTranscriptionPreferences",
                type: "character varying(16)",
                maxLength: 16,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "character varying(16)",
                oldMaxLength: 16);
        }
    }
}
