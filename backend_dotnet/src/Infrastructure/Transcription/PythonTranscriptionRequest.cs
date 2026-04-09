using System.Text.Json.Serialization;
using System.Text.Json;

namespace Infrastructure.Transcription;

public sealed class PythonTranscriptionRequest
{
    [JsonPropertyName("sourceType")]
    public string SourceType { get; set; } = "file_path";

    [JsonPropertyName("sourceValue")]
    public string SourceValue { get; set; } = "";

    [JsonPropertyName("model")]
    public string Model { get; set; } = "large-v3";

    [JsonPropertyName("task")]
    public string Task { get; set; } = "transcribe";

    [JsonPropertyName("language")]
    public string Language { get; set; } = "auto";

    [JsonPropertyName("outputFormat")]
    public string OutputFormat { get; set; } = "srt";

    [JsonPropertyName("requestedOutputs")]
    public List<string>? RequestedOutputs { get; set; }

    [JsonPropertyName("requestedOutputsCsv")]
    public string? RequestedOutputsCsv { get; set; }

    [JsonPropertyName("deliveryMode")]
    public string? DeliveryMode { get; set; }

    [JsonPropertyName("generateSubtitles")]
    public bool GenerateSubtitles { get; set; } = true;

    [JsonPropertyName("burnSubtitlesIntoVideo")]
    public bool BurnSubtitlesIntoVideo { get; set; }

    [JsonPropertyName("keepTimestamps")]
    public bool KeepTimestamps { get; set; } = true;

    [JsonPropertyName("splitBySentence")]
    public bool SplitBySentence { get; set; } = true;

    [JsonPropertyName("wordTimestamps")]
    public bool WordTimestamps { get; set; }

    [JsonPropertyName("vadFilter")]
    public bool VadFilter { get; set; } = true;

    [JsonPropertyName("devicePreference")]
    public string DevicePreference { get; set; } = "auto";

    [JsonPropertyName("computeType")]
    public string ComputeType { get; set; } = "float16";

    [JsonPropertyName("beamSize")]
    public int BeamSize { get; set; } = 5;

    [JsonPropertyName("maxSubtitleChars")]
    public int? MaxSubtitleChars { get; set; } = 42;

    [JsonPropertyName("subtitleStyle")]
    public string SubtitleStyle { get; set; } = "default";

    [JsonPropertyName("subtitleVisualPreset")]
    public string? SubtitleVisualPreset { get; set; }

    [JsonPropertyName("targetLanguages")]
    public List<string>? TargetLanguages { get; set; }

    [JsonPropertyName("videoDeliveryMode")]
    public string? VideoDeliveryMode { get; set; }

    [JsonPropertyName("aiEnhancementEnabled")]
    public bool AiEnhancementEnabled { get; set; }

    [JsonPropertyName("aiProvider")]
    public string? AiProvider { get; set; }

    [JsonPropertyName("aiModel")]
    public string? AiModel { get; set; }

    [JsonPropertyName("aiMode")]
    public string? AiMode { get; set; }

    [JsonPropertyName("aiPrompt")]
    public string? AiPrompt { get; set; }

    [JsonPropertyName("aiTemperature")]
    public double? AiTemperature { get; set; }

    [JsonPropertyName("aiTopP")]
    public double? AiTopP { get; set; }

    [JsonPropertyName("aiMaxTokens")]
    public int? AiMaxTokens { get; set; }

    [JsonPropertyName("aiChunkChars")]
    public int? AiChunkChars { get; set; }

    [JsonPropertyName("aiUseVisualContext")]
    public bool AiUseVisualContext { get; set; }

    [JsonPropertyName("aiFrameSampleSeconds")]
    public int? AiFrameSampleSeconds { get; set; }

    [JsonPropertyName("preserveTimestamps")]
    public bool PreserveTimestamps { get; set; } = true;

    [JsonPropertyName("aiRevisionPasses")]
    public int AiRevisionPasses { get; set; } = 3;

    [JsonPropertyName("useAdvancedAlignment")]
    public string UseAdvancedAlignment { get; set; } = "auto";

    [JsonPropertyName("enableOnlineContext")]
    public bool EnableOnlineContext { get; set; }

    [JsonPropertyName("contextHints")]
    public JsonElement? ContextHints { get; set; }

    [JsonPropertyName("qualityProfile")]
    public string QualityProfile { get; set; } = "balanced";

    [JsonPropertyName("contentMode")]
    public string ContentMode { get; set; } = "episode";

    [JsonPropertyName("speakerStyleMode")]
    public string SpeakerStyleMode { get; set; } = "heuristic";

    [JsonPropertyName("styleIntensity")]
    public string StyleIntensity { get; set; } = "thematic";

    [JsonPropertyName("renderedPreviewMode")]
    public string RenderedPreviewMode { get; set; } = "fast";

    [JsonPropertyName("animeSongLayoutMode")]
    public string AnimeSongLayoutMode { get; set; } = "off";

    [JsonPropertyName("karaokeGranularity")]
    public string KaraokeGranularity { get; set; } = "off";

    [JsonPropertyName("jobId")]
    public string? JobId { get; set; }

    [JsonPropertyName("progressCallbackUrl")]
    public string? ProgressCallbackUrl { get; set; }

    [JsonPropertyName("progressCallbackToken")]
    public string? ProgressCallbackToken { get; set; }
}
