using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace Domain.Entities;

public class TranscriptionJob
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public Guid Id { get; set; } = Guid.NewGuid();

    public string UserId { get; set; } = "";

    public string SourceType { get; set; } = "file_path"; // url | file_path
    public string SourceValue { get; set; } = "";

    // snapshot principal da execução
    public string Model { get; set; } = "large-v3"; // ASR / faster-whisper
    public string Task { get; set; } = "transcribe"; // transcribe | translate
    public string Language { get; set; } = "auto";
    public string OutputFormat { get; set; } = "srt";

    // contrato já em migração no front/controller
    public string RequestedOutputsJson { get; set; } = "[\"srt\"]";
    public string DeliveryMode { get; set; } = "standard"; // standard | video_only

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

    // próxima fase: tradução multi-idioma
    public string TargetLanguagesJson { get; set; } = "[]";
    public string VideoDeliveryMode { get; set; } = "standard";
    // standard | video_only | mux_subtitles | burned_video

    // próxima fase: IA / Ollama
    public bool AiEnhancementEnabled { get; set; } = false;
    public string AiProvider { get; set; } = "ollama_project";
    public string AiModel { get; set; } = "qwen2.5vl:7b";
    public string AiMode { get; set; } = "correction";
    // correction | semantic_translation | subtitle_styling

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

    public string Status { get; set; } = "pending"; // pending | processing | completed | error | canceled
    public int ProgressPercent { get; set; } = 0;
    public string CurrentStage { get; set; } = "pending";
    public int CurrentPass { get; set; } = 0;
    public int TotalPasses { get; set; } = 0;

    public string? ErrorMessage { get; set; }
    public string? LanguageDetected { get; set; }
    public double? DurationSeconds { get; set; }
    public string? QualitySummaryJson { get; set; }
    public string? TranslationStatusesJson { get; set; }
    public string? StyleSource { get; set; }
    public string? CapabilityProfileJson { get; set; }
    public string? DetectedContentType { get; set; }
    public double? ContentDetectionConfidence { get; set; }
    public string? SpeakerModeApplied { get; set; }
    public string? KaraokeModeApplied { get; set; }

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime? StartedAtUtc { get; set; }
    public DateTime? FinishedAtUtc { get; set; }

    public ICollection<TranscriptionJobOutput> Outputs { get; set; } = new List<TranscriptionJobOutput>();

    public List<string> GetRequestedOutputs()
    {
        return DeserializeStringList(RequestedOutputsJson, new[] { "srt" });
    }

    public void SetRequestedOutputs(IEnumerable<string>? values)
    {
        RequestedOutputsJson = SerializeStringList(values, new[] { "srt" });
    }

    public List<string> GetTargetLanguages()
    {
        return DeserializeStringList(TargetLanguagesJson, Array.Empty<string>());
    }

    public void SetTargetLanguages(IEnumerable<string>? values)
    {
        TargetLanguagesJson = SerializeStringList(values, Array.Empty<string>());
    }

    private static string SerializeStringList(IEnumerable<string>? values, IEnumerable<string> fallback)
    {
        var list = (values ?? fallback)
            .Select(x => (x ?? string.Empty).Trim().ToLowerInvariant())
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        return JsonSerializer.Serialize(list, JsonOptions);
    }

    private static List<string> DeserializeStringList(string? raw, IEnumerable<string> fallback)
    {
        if (!string.IsNullOrWhiteSpace(raw))
        {
            try
            {
                var parsed = JsonSerializer.Deserialize<List<string>>(raw, JsonOptions);
                if (parsed is { Count: > 0 })
                {
                    return parsed
                        .Select(x => (x ?? string.Empty).Trim().ToLowerInvariant())
                        .Where(x => !string.IsNullOrWhiteSpace(x))
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .ToList();
                }
            }
            catch
            {
                // fallback silencioso para jobs antigos
            }
        }

        return fallback
            .Select(x => (x ?? string.Empty).Trim().ToLowerInvariant())
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }
}
