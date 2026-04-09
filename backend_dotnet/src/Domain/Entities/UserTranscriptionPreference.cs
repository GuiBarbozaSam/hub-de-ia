using System;

namespace Domain.Entities;

public sealed class UserTranscriptionPreference
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string UserId { get; set; } = string.Empty;

    public string SourceTypeDefault { get; set; } = "file_path";
    public string Model { get; set; } = "large-v3";
    public string Task { get; set; } = "transcribe";
    public string Language { get; set; } = "auto";
    public string OutputFormat { get; set; } = "srt";

    public string RequestedOutputsJson { get; set; } = "[\"srt\"]";
    public string DeliveryMode { get; set; } = "standard";

    public bool GenerateSubtitles { get; set; } = true;
    public bool BurnSubtitlesIntoVideo { get; set; } = false;
    public bool KeepTimestamps { get; set; } = true;
    public bool SplitBySentence { get; set; } = true;
    public bool WordTimestamps { get; set; } = false;
    public bool VadFilter { get; set; } = true;

    public string DevicePreference { get; set; } = "auto";
    public string ComputeType { get; set; } = "float16";
    public int BeamSize { get; set; } = 5;
    public int? MaxSubtitleChars { get; set; } = 42;
    public string SubtitleStyle { get; set; } = "default";

    public string TargetLanguagesJson { get; set; } = "[]";
    public string VideoDeliveryMode { get; set; } = "standard";

    public bool AiEnhancementEnabled { get; set; } = false;
    public string AiProvider { get; set; } = "ollama_project";
    public string AiModel { get; set; } = "qwen2.5vl:7b";
    public string AiMode { get; set; } = "correction";
    public string? AiPrompt { get; set; }
    public double? AiTemperature { get; set; } = 0.2;
    public double? AiTopP { get; set; } = 0.9;
    public int? AiMaxTokens { get; set; } = 1024;
    public int? AiChunkChars { get; set; } = 6000;
    public bool AiUseVisualContext { get; set; } = false;
    public int? AiFrameSampleSeconds { get; set; } = 12;
    public bool PreserveTimestamps { get; set; } = true;
    public int AiRevisionPasses { get; set; } = 3;
    public string UseAdvancedAlignment { get; set; } = "auto";
    public bool EnableOnlineContext { get; set; } = false;
    public string? ContextHintsJson { get; set; }
    public string QualityProfile { get; set; } = "balanced";
    public string ContentMode { get; set; } = "episode";
    public string SpeakerStyleMode { get; set; } = "heuristic";
    public string StyleIntensity { get; set; } = "thematic";
    public string RenderedPreviewMode { get; set; } = "fast";
    public string AnimeSongLayoutMode { get; set; } = "off";
    public string KaraokeGranularity { get; set; } = "off";

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAtUtc { get; set; } = DateTime.UtcNow;
}
