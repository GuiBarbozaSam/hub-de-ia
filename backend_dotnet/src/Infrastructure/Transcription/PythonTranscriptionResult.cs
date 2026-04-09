using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Infrastructure.Transcription;

public sealed class PythonTranscriptionResult
{
    [JsonPropertyName("status")]
    public string Status { get; set; } = "error";

    [JsonPropertyName("text")]
    public string? Text { get; set; }

    [JsonPropertyName("srt")]
    public string? Srt { get; set; }

    [JsonPropertyName("vtt")]
    public string? Vtt { get; set; }

    [JsonPropertyName("assPath")]
    public string? AssPath { get; set; }

    [JsonPropertyName("videoOutputPath")]
    public string? VideoOutputPath { get; set; }

    [JsonPropertyName("videoMuxedPath")]
    public string? VideoMuxedPath { get; set; }

    [JsonPropertyName("renderPreviewPath")]
    public string? RenderPreviewPath { get; set; }

    [JsonPropertyName("karaokePlanPath")]
    public string? KaraokePlanPath { get; set; }

    [JsonPropertyName("sceneMapPath")]
    public string? SceneMapPath { get; set; }

    [JsonPropertyName("speakerMapPath")]
    public string? SpeakerMapPath { get; set; }

    [JsonPropertyName("lyricAlignmentPath")]
    public string? LyricAlignmentPath { get; set; }

    [JsonPropertyName("translationManifestPath")]
    public string? TranslationManifestPath { get; set; }

    [JsonPropertyName("diagnosticsPath")]
    public string? DiagnosticsPath { get; set; }

    [JsonPropertyName("enhancedDirPath")]
    public string? EnhancedDirPath { get; set; }

    [JsonPropertyName("outputDirPath")]
    public string? OutputDirPath { get; set; }

    [JsonPropertyName("warnings")]
    public List<string>? Warnings { get; set; }

    [JsonPropertyName("diagnostics")]
    public List<PythonJobDiagnostic>? Diagnostics { get; set; }

    [JsonPropertyName("styleSource")]
    public string? StyleSource { get; set; }

    [JsonPropertyName("detectedContentType")]
    public string? DetectedContentType { get; set; }

    [JsonPropertyName("contentDetectionConfidence")]
    public double? ContentDetectionConfidence { get; set; }

    [JsonPropertyName("speakerModeApplied")]
    public string? SpeakerModeApplied { get; set; }

    [JsonPropertyName("karaokeModeApplied")]
    public string? KaraokeModeApplied { get; set; }

    [JsonPropertyName("voiceAnalysisSource")]
    public string? VoiceAnalysisSource { get; set; }

    [JsonPropertyName("sceneAnalysisSource")]
    public string? SceneAnalysisSource { get; set; }

    [JsonPropertyName("previewModeApplied")]
    public string? PreviewModeApplied { get; set; }

    [JsonPropertyName("plannerModelUsed")]
    public string? PlannerModelUsed { get; set; }

    [JsonPropertyName("reviewModelUsed")]
    public string? ReviewModelUsed { get; set; }

    [JsonPropertyName("timeoutProfileApplied")]
    public string? TimeoutProfileApplied { get; set; }

    [JsonPropertyName("requestedAiProvider")]
    public string? RequestedAiProvider { get; set; }

    [JsonPropertyName("requestedAiModel")]
    public string? RequestedAiModel { get; set; }

    [JsonPropertyName("effectiveAiProvider")]
    public string? EffectiveAiProvider { get; set; }

    [JsonPropertyName("effectiveAiModel")]
    public string? EffectiveAiModel { get; set; }

    [JsonPropertyName("runtimeTarget")]
    public string? RuntimeTarget { get; set; }

    [JsonPropertyName("modelInstalledAtSubmission")]
    public bool? ModelInstalledAtSubmission { get; set; }

    [JsonPropertyName("fallbacks")]
    public List<Dictionary<string, object?>>? Fallbacks { get; set; }

    [JsonPropertyName("currentStage")]
    public string? CurrentStage { get; set; }

    [JsonPropertyName("currentPass")]
    public int? CurrentPass { get; set; }

    [JsonPropertyName("totalPasses")]
    public int? TotalPasses { get; set; }

    [JsonPropertyName("qualitySummary")]
    public Dictionary<string, object?>? QualitySummary { get; set; }

    [JsonPropertyName("translationStatuses")]
    public Dictionary<string, object?>? TranslationStatuses { get; set; }

    [JsonPropertyName("capabilityProfile")]
    public Dictionary<string, object?>? CapabilityProfile { get; set; }

    [JsonPropertyName("qualityReportPath")]
    public string? QualityReportPath { get; set; }

    [JsonPropertyName("styleMapPath")]
    public string? StyleMapPath { get; set; }

    [JsonPropertyName("alignmentReportPath")]
    public string? AlignmentReportPath { get; set; }

    [JsonPropertyName("error")]
    public string? Error { get; set; }

    [JsonPropertyName("languageDetected")]
    public string? LanguageDetected { get; set; }

    [JsonPropertyName("durationSeconds")]
    public double? DurationSeconds { get; set; }

    [JsonPropertyName("sourceDurationSeconds")]
    public double? SourceDurationSeconds { get; set; }

    [JsonPropertyName("outputDurationSeconds")]
    public double? OutputDurationSeconds { get; set; }

    [JsonPropertyName("musicalSegmentDurations")]
    public List<Dictionary<string, object?>>? MusicalSegmentDurations { get; set; }
}

public sealed class PythonJobDiagnostic
{
    [JsonPropertyName("stage")]
    public string Stage { get; set; } = "";

    [JsonPropertyName("severity")]
    public string Severity { get; set; } = "";

    [JsonPropertyName("message")]
    public string Message { get; set; } = "";

    [JsonPropertyName("model")]
    public string? Model { get; set; }

    [JsonPropertyName("language")]
    public string? Language { get; set; }

    [JsonPropertyName("fallbackUsed")]
    public string? FallbackUsed { get; set; }

    [JsonPropertyName("rawExcerpt")]
    public string? RawExcerpt { get; set; }

    [JsonPropertyName("sourceField")]
    public string? SourceField { get; set; }

    [JsonPropertyName("durationMs")]
    public int? DurationMs { get; set; }
}

public sealed class PythonTranscriptionCapabilities
{
    [JsonPropertyName("service")]
    public string Service { get; set; } = "transcription";

    [JsonPropertyName("faster_whisper_installed")]
    public bool FasterWhisperInstalled { get; set; }

    [JsonPropertyName("default_model")]
    public string? DefaultModel { get; set; }

    [JsonPropertyName("device_mode")]
    public string? DeviceMode { get; set; }

    [JsonPropertyName("compute_type_mode")]
    public string? ComputeTypeMode { get; set; }

    [JsonPropertyName("hardware")]
    public Dictionary<string, object?> Hardware { get; set; } = new();

    [JsonPropertyName("ollama")]
    public Dictionary<string, object?>? Ollama { get; set; }

    [JsonPropertyName("profiles")]
    public Dictionary<string, object?>? Profiles { get; set; }

    [JsonPropertyName("recommendedProfile")]
    public string? RecommendedProfile { get; set; }

    [JsonPropertyName("jobTimeoutMinutes")]
    public int? JobTimeoutMinutes { get; set; }

    [JsonPropertyName("structuredTimeoutSeconds")]
    public int? StructuredTimeoutSeconds { get; set; }

    [JsonPropertyName("styleTimeoutSeconds")]
    public int? StyleTimeoutSeconds { get; set; }

    [JsonPropertyName("timeoutProfileApplied")]
    public string? TimeoutProfileApplied { get; set; }

    [JsonPropertyName("projectRuntime")]
    public Dictionary<string, object?>? ProjectRuntime { get; set; }

    [JsonPropertyName("hostRuntime")]
    public Dictionary<string, object?>? HostRuntime { get; set; }

    [JsonPropertyName("providers")]
    public List<Dictionary<string, object?>>? Providers { get; set; }

    [JsonPropertyName("installedModelsByProvider")]
    public Dictionary<string, object?>? InstalledModelsByProvider { get; set; }

    [JsonPropertyName("downloadableModelsByProvider")]
    public Dictionary<string, object?>? DownloadableModelsByProvider { get; set; }

    [JsonPropertyName("activeModelStorePath")]
    public string? ActiveModelStorePath { get; set; }
}
