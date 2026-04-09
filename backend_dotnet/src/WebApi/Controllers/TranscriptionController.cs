using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Domain.Entities;
using Infrastructure.Persistence;
using Infrastructure.Storage;
using Infrastructure.Transcription;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace WebApi.Controllers;

[ApiController]
[Route("api/transcription")]
[Authorize]
public sealed class TranscriptionController : ControllerBase
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    private static readonly string[] AllowedSourceTypes = ["url", "file_path"];
    private static readonly string[] AllowedJobCreationModes = ["upload", "url", "file_path"];
    private static readonly string[] AllowedModels = ["tiny", "base", "small", "medium", "large-v3"];
    private static readonly string[] AllowedTasks = ["transcribe", "translate"];
    private static readonly string[] AllowedLanguages = ["auto", "pt", "en", "es", "fr", "de", "it", "ja", "ko", "zh", "zh-cn", "ru", "ar", "hi"];
    private static readonly string[] AllowedDevices = ["auto", "cpu", "gpu:0", "gpu:1"];
    private static readonly string[] AllowedComputeTypes = ["float16", "int8", "int8_float16", "float32"];
    private static readonly string[] AllowedStatuses = ["pending", "processing", "completed", "error", "canceled"];
    private static readonly string[] AllowedSubtitleStyles = ["default", "clean", "highlight", "cinematic", "shorts_bold", "shorts_dynamic", "shorts_neon"];
    private static readonly string[] AllowedAiProviders = ["ollama_project", "remote_api"];
    private static readonly string[] AllowedAiModes = ["correction", "semantic_translation", "subtitle_styling"];
    private static readonly string[] AllowedAiModels =
    [
        "qwen2.5vl:7b",
        "qwen2.5vl:32b",
        "qwen3-vl:30b-a3b-instruct-q4_K_M"
    ];
    private static readonly string[] AllowedTargetLanguages = ["pt-BR", "en", "es", "fr", "de", "it", "ja", "ko", "zh-CN", "ru", "ar", "hi"];
    private static readonly string[] AllowedVideoDeliveryModes = ["standard", "video_only", "mux_subtitles", "burned_video"];
    private static readonly string[] AllowedTextOutputs = ["txt", "srt", "vtt", "ass"];
    private static readonly string[] AllowedAlignmentModes = ["auto", "on", "off"];
    private static readonly string[] AllowedQualityProfiles = ["safe", "balanced", "max"];
    private static readonly string[] AllowedContentModes = ["auto", "episode", "anime_song"];
    private static readonly string[] AllowedSpeakerStyleModes = ["off", "heuristic", "advanced"];
    private static readonly string[] AllowedStyleIntensities = ["subtle", "thematic", "expressive"];
    private static readonly string[] AllowedRenderedPreviewModes = ["fast", "rendered"];
    private static readonly string[] AllowedAnimeSongLayoutModes = ["off", "romaji_top_translation_bottom"];
    private static readonly string[] AllowedKaraokeGranularities = ["off", "word", "syllable"];

    private readonly AppDbContext _db;
    private readonly ILocalMediaStorage _storage;
    private readonly PythonTranscriptionClient _pythonClient;
    private readonly PythonTranscriptionSettings _pythonSettings;

    public TranscriptionController(
        AppDbContext db,
        ILocalMediaStorage storage,
        PythonTranscriptionClient pythonClient,
        PythonTranscriptionSettings pythonSettings)
    {
        _db = db;
        _storage = storage;
        _pythonClient = pythonClient;
        _pythonSettings = pythonSettings;
    }

    [HttpGet("options")]
    public async Task<IActionResult> GetOptions(CancellationToken ct)
    {
        var capabilities = await _pythonClient.GetCapabilitiesAsync(ct);
        var providerCatalog = (capabilities.Providers ?? new List<Dictionary<string, object?>>())
            .Select(provider => new
            {
                id = ReadCapabilityString(provider, "id") ?? "ollama_project",
                label = ReadCapabilityString(provider, "label") ?? "Provider",
                type = ReadCapabilityString(provider, "type") ?? "ollama",
                available = ReadCapabilityBool(provider, "available"),
                installedModels = ReadCapabilityStringList(provider, "installedModels"),
                downloadableModels = ReadCapabilityStringList(provider, "downloadableModels"),
                multimodalModels = ReadCapabilityStringList(provider, "multimodalModels"),
                defaultModel = ReadCapabilityString(provider, "defaultModel")
            })
            .ToList();

        var installedByProvider = ReadCapabilityStringDictionaryOfLists(capabilities.InstalledModelsByProvider);
        var downloadableByProvider = ReadCapabilityStringDictionaryOfLists(capabilities.DownloadableModelsByProvider);
        var defaultProvider = providerCatalog
            .FirstOrDefault(x => x.available && string.Equals(x.id, "ollama_project", StringComparison.OrdinalIgnoreCase))
            ?.id
            ?? providerCatalog.FirstOrDefault(x => x.available)?.id
            ?? "ollama_project";
        var defaultProviderInfo = providerCatalog.FirstOrDefault(x => string.Equals(x.id, defaultProvider, StringComparison.OrdinalIgnoreCase));
        var installedModels = installedByProvider.TryGetValue(defaultProvider, out var providerInstalled)
            ? providerInstalled
                .Where(model => defaultProviderInfo is null || defaultProviderInfo.multimodalModels.Contains(model, StringComparer.OrdinalIgnoreCase))
                .ToList()
            : [];

        return Ok(new
        {
            sourceTypes = AllowedSourceTypes,
            jobCreationModes = AllowedJobCreationModes,
            models = AllowedModels,
            tasks = AllowedTasks,
            languages = AllowedLanguages,
            outputFormats = new[] { "txt", "srt", "vtt", "ass", "all", "video_only" },
            deliveryModes = AllowedVideoDeliveryModes,
            devices = AllowedDevices,
            computeTypes = AllowedComputeTypes,
            statuses = AllowedStatuses,
            subtitleStyles = AllowedSubtitleStyles,
            subtitleVisualPresets = AllowedSubtitleStyles,
            aiProviders = providerCatalog.Select(x => x.id).ToArray(),
            aiModes = AllowedAiModes,
            aiModels = installedModels,
            aiProviderCatalog = providerCatalog,
            installedAiModelsByProvider = installedByProvider,
            downloadableAiModelsByProvider = downloadableByProvider,
            defaultAiProvider = defaultProvider,
            targetLanguages = AllowedTargetLanguages,
            alignmentModes = AllowedAlignmentModes,
            qualityProfiles = AllowedQualityProfiles,
            contentModes = AllowedContentModes,
            speakerStyleModes = AllowedSpeakerStyleModes,
            styleIntensities = AllowedStyleIntensities,
            renderedPreviewModes = AllowedRenderedPreviewModes,
            animeSongLayoutModes = AllowedAnimeSongLayoutModes,
            karaokeGranularities = AllowedKaraokeGranularities
        });
    }

    [HttpGet("capabilities")]
    public async Task<IActionResult> GetCapabilities(CancellationToken ct)
    {
        var capabilities = await _pythonClient.GetCapabilitiesAsync(ct);
        var recommendedProfile = capabilities.RecommendedProfile ?? "balanced";
        var selectedProfile = ReadCapabilityDictionary(capabilities.Profiles, recommendedProfile);
        return Ok(new
        {
            capabilities.Service,
            fasterWhisperInstalled = capabilities.FasterWhisperInstalled,
            defaultModel = capabilities.DefaultModel,
            deviceMode = capabilities.DeviceMode,
            computeTypeMode = capabilities.ComputeTypeMode,
            hardware = capabilities.Hardware,
            ollama = capabilities.Ollama,
            projectRuntime = capabilities.ProjectRuntime,
            hostRuntime = capabilities.HostRuntime,
            providers = capabilities.Providers,
            profiles = capabilities.Profiles,
            recommendedProfile = capabilities.RecommendedProfile,
            diarizationAvailable = ReadCapabilityBool(capabilities.Hardware, "diarizationAvailable"),
            advancedAlignmentAvailable = ReadCapabilityBool(capabilities.Hardware, "advancedAlignmentAvailable"),
            voiceAnalysisAvailable = ReadCapabilityBool(capabilities.Hardware, "voiceAnalysisAvailable", fallback: true),
            sceneAnalysisAvailable = ReadCapabilityBool(capabilities.Hardware, "sceneAnalysisAvailable", fallback: true),
            maxSupportedKaraokeGranularity = ReadCapabilityString(capabilities.Hardware, "maxSupportedKaraokeGranularity"),
            installedModels = ReadCapabilityStringList(capabilities.Ollama, "installedModels"),
            installedModelsByProvider = ReadCapabilityStringDictionaryOfLists(capabilities.InstalledModelsByProvider),
            downloadableModelsByProvider = ReadCapabilityStringDictionaryOfLists(capabilities.DownloadableModelsByProvider),
            activeModelStorePath = capabilities.ActiveModelStorePath,
            jobTimeoutMinutes = capabilities.JobTimeoutMinutes ?? _pythonSettings.TimeoutMinutes,
            structuredTimeoutSeconds = capabilities.StructuredTimeoutSeconds ?? ReadCapabilityInt(selectedProfile, "structuredTimeoutSeconds"),
            styleTimeoutSeconds = capabilities.StyleTimeoutSeconds ?? ReadCapabilityInt(selectedProfile, "styleTimeoutSeconds"),
            timeoutProfileApplied = capabilities.TimeoutProfileApplied ?? recommendedProfile
        });
    }

    [HttpPost("models/download")]
    public async Task<IActionResult> StartModelDownload([FromBody] ModelDownloadRequest request, CancellationToken ct)
    {
        var provider = NormalizeAiProvider(request.Provider);
        var model = NormalizeAiModel(request.Model);
        if (string.IsNullOrWhiteSpace(model))
        {
            return BadRequest(new { message = "Modelo é obrigatório." });
        }

        var capabilities = await _pythonClient.GetCapabilitiesAsync(ct);
        var downloadable = ReadCapabilityStringDictionaryOfLists(capabilities.DownloadableModelsByProvider);
        var installed = ReadCapabilityStringDictionaryOfLists(capabilities.InstalledModelsByProvider);

        if (installed.TryGetValue(provider, out var installedModels) &&
            installedModels.Contains(model, StringComparer.OrdinalIgnoreCase))
        {
            return Ok(new
            {
                id = $"model-{Guid.NewGuid():N}",
                provider,
                model,
                status = "completed",
                progress = 100,
                detail = "Modelo já está instalado no runtime do projeto."
            });
        }

        if (!downloadable.TryGetValue(provider, out var downloadableModels) ||
            !downloadableModels.Contains(model, StringComparer.OrdinalIgnoreCase))
        {
            return BadRequest(new { message = $"O modelo '{model}' não está disponível para download no provider '{provider}'." });
        }

        var started = await _pythonClient.StartModelDownloadAsync(provider, model, ct);
        return Ok(started);
    }

    [HttpGet("models/downloads/{downloadId}")]
    public async Task<IActionResult> GetModelDownloadStatus([FromRoute] string downloadId, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(downloadId))
        {
            return BadRequest(new { message = "downloadId é obrigatório." });
        }

        var current = await _pythonClient.GetModelDownloadStatusAsync(downloadId, ct);
        return Ok(current);
    }

    [HttpGet("preferences")]
    public async Task<IActionResult> GetPreferences(CancellationToken ct)
    {
        var userId = GetUserId();

        var preference = await _db.UserTranscriptionPreferences
            .AsNoTracking()
            .FirstOrDefaultAsync(x => x.UserId == userId, ct);

        if (preference is null)
        {
            return Ok(BuildDefaultPreferencesResponse());
        }

        return Ok(ToPreferenceResponse(preference));
    }

    [HttpPut("preferences")]
    public async Task<IActionResult> SavePreferences([FromBody] SaveTranscriptionPreferencesRequest request, CancellationToken ct)
    {
        var userId = GetUserId();

        var preference = await _db.UserTranscriptionPreferences
            .FirstOrDefaultAsync(x => x.UserId == userId, ct);

        if (preference is null)
        {
            preference = new UserTranscriptionPreference
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                CreatedAtUtc = DateTime.UtcNow
            };
            _db.UserTranscriptionPreferences.Add(preference);
        }

        ApplyPreferenceRequest(preference, request);
        var aiValidationError = await ValidateAiRuntimeSelectionAsync(
            preference.AiEnhancementEnabled,
            preference.AiProvider,
            preference.AiModel,
            ct);
        if (!string.IsNullOrWhiteSpace(aiValidationError))
        {
            return BadRequest(new { message = aiValidationError });
        }
        preference.UpdatedAtUtc = DateTime.UtcNow;

        await _db.SaveChangesAsync(ct);
        return Ok(ToPreferenceResponse(preference));
    }

    [HttpPost("preferences/reset")]
    public async Task<IActionResult> ResetPreferences(CancellationToken ct)
    {
        var userId = GetUserId();

        var preference = await _db.UserTranscriptionPreferences
            .FirstOrDefaultAsync(x => x.UserId == userId, ct);

        if (preference is not null)
        {
            _db.UserTranscriptionPreferences.Remove(preference);
            await _db.SaveChangesAsync(ct);
        }

        return Ok(BuildDefaultPreferencesResponse());
    }

    [HttpGet("jobs")]
    public async Task<IActionResult> ListJobs(CancellationToken ct)
    {
        var userId = GetUserId();

        var jobs = await _db.TranscriptionJobs
            .AsNoTracking()
            .Where(x => x.UserId == userId)
            .OrderByDescending(x => x.CreatedAtUtc)
            .Take(100)
            .Select(x => new
            {
                x.Id,
                x.SourceType,
                SourceValue = ToClientSourceValue(x.SourceType, x.SourceValue),
                x.Model,
                x.Task,
                x.Status,
                x.ProgressPercent,
                x.CreatedAtUtc,
                x.FinishedAtUtc
            })
            .ToListAsync(ct);

        return Ok(jobs);
    }

    [HttpGet("jobs/{id:guid}")]
    public async Task<IActionResult> GetJob([FromRoute] Guid id, CancellationToken ct)
    {
        var userId = GetUserId();

        var job = await _db.TranscriptionJobs
            .AsNoTracking()
            .Include(x => x.Outputs)
            .FirstOrDefaultAsync(x => x.Id == id && x.UserId == userId, ct);

        if (job is null)
        {
            return NotFound();
        }

        return Ok(ToJobResponse(job));
    }

    [HttpPost("jobs")]
    public async Task<IActionResult> CreateJob([FromBody] CreateTranscriptionJobRequest request, CancellationToken ct)
    {
        var userId = GetUserId();
        var sourceType = NormalizeSourceType(request.SourceType);
        var sourceValue = (request.SourceValue ?? string.Empty).Trim();

        if (string.IsNullOrWhiteSpace(sourceValue))
        {
            return BadRequest(new { message = "sourceValue é obrigatório." });
        }

        var job = BuildJobFromRequest(userId, sourceType, sourceValue, request);
        var aiValidationError = await ValidateAiRuntimeSelectionAsync(
            job.AiEnhancementEnabled,
            job.AiProvider,
            job.AiModel,
            ct);
        if (!string.IsNullOrWhiteSpace(aiValidationError))
        {
            return BadRequest(new { message = aiValidationError });
        }
        _db.TranscriptionJobs.Add(job);
        await _db.SaveChangesAsync(ct);

        return Ok(await BuildJobResponseAsync(job.Id, userId, ct));
    }

    [HttpPost("jobs/upload")]
    [RequestSizeLimit(2_000_000_000)]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> CreateUploadJob([FromForm] CreateTranscriptionUploadRequest request, CancellationToken ct)
    {
        var userId = GetUserId();

        if (request.File is null || request.File.Length <= 0)
        {
            return BadRequest(new { message = "Arquivo inválido." });
        }

        var stored = await _storage.SaveSourceUploadAsync(request.File, userId, ct);
        var job = BuildJobFromUpload(userId, stored.RelativePath, request);
        var aiValidationError = await ValidateAiRuntimeSelectionAsync(
            job.AiEnhancementEnabled,
            job.AiProvider,
            job.AiModel,
            ct);
        if (!string.IsNullOrWhiteSpace(aiValidationError))
        {
            return BadRequest(new { message = aiValidationError });
        }

        _db.TranscriptionJobs.Add(job);
        await _db.SaveChangesAsync(ct);

        return Ok(await BuildJobResponseAsync(job.Id, userId, ct));
    }

    [HttpGet("outputs/{id:guid}/preview")]
    public async Task<IActionResult> PreviewOutput([FromRoute] Guid id, CancellationToken ct)
    {
        var output = await GetOwnedOutputAsync(id, ct);
        if (output is null) return NotFound();

        if (!string.IsNullOrWhiteSpace(output.ContentText))
        {
            return Content(output.ContentText, GetOutputContentType(output.OutputType));
        }

        if (string.IsNullOrWhiteSpace(output.FilePath))
        {
            return NotFound();
        }

        var path = _storage.ResolveManagedFilePath(output.FilePath);
        return PhysicalFile(path, _storage.GetContentType(path), enableRangeProcessing: true);
    }

    [HttpGet("outputs/{id:guid}/download")]
    public async Task<IActionResult> DownloadOutput([FromRoute] Guid id, CancellationToken ct)
    {
        var output = await GetOwnedOutputAsync(id, ct);
        if (output is null) return NotFound();

        var fileName = BuildDownloadFileName(output);

        if (!string.IsNullOrWhiteSpace(output.ContentText))
        {
            var bytes = Encoding.UTF8.GetBytes(output.ContentText);
            return File(bytes, GetOutputContentType(output.OutputType), fileName);
        }

        if (string.IsNullOrWhiteSpace(output.FilePath))
        {
            return NotFound();
        }

        var path = _storage.ResolveManagedFilePath(output.FilePath);
        return PhysicalFile(path, _storage.GetContentType(path), fileName, enableRangeProcessing: true);
    }

    [HttpGet("outputs/{id:guid}/preview-page")]
    public async Task<IActionResult> PreviewPage([FromRoute] Guid id, CancellationToken ct)
    {
        var output = await GetOwnedOutputAsync(id, ct);
        if (output is null) return NotFound();

        var previewKind = GetPreviewKind(output);
        var previewUrl = Url.Action(nameof(PreviewOutput), new { id = output.Id }) ?? $"/api/transcription/outputs/{output.Id}/preview";
        var safeTitle = System.Net.WebUtility.HtmlEncode(BuildDownloadFileName(output));

        if (previewKind == "text")
        {
            return Content($$"""
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>{{safeTitle}}</title>
  <style>
    body { background:#0f1117; color:#f5f7fa; font-family:Segoe UI,Arial,sans-serif; margin:0; padding:24px; }
    pre { white-space:pre-wrap; word-wrap:break-word; background:#151925; border:1px solid #2a3145; border-radius:16px; padding:20px; line-height:1.55; }
  </style>
</head>
<body>
  <pre id="content">Carregando...</pre>
  <script>
    fetch('{{previewUrl}}', { credentials: 'include' })
      .then(r => r.text())
      .then(t => document.getElementById('content').textContent = t)
      .catch(() => document.getElementById('content').textContent = 'Falha ao carregar preview.');
  </script>
</body>
</html>
""", "text/html; charset=utf-8");
        }

        if (previewKind == "video")
        {
            return Content($$"""
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>{{safeTitle}}</title>
  <style>
    body { background:#0b0d13; color:#f5f7fa; font-family:Segoe UI,Arial,sans-serif; margin:0; display:flex; align-items:center; justify-content:center; min-height:100vh; }
    video { width:min(96vw,1200px); height:auto; max-height:92vh; border-radius:18px; background:#000; }
  </style>
</head>
<body>
  <video controls autoplay playsinline src="{{previewUrl}}"></video>
</body>
</html>
""", "text/html; charset=utf-8");
        }

        if (previewKind == "audio")
        {
            return Content($$"""
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>{{safeTitle}}</title>
  <style>
    body { background:#0b0d13; color:#f5f7fa; font-family:Segoe UI,Arial,sans-serif; margin:0; display:flex; align-items:center; justify-content:center; min-height:100vh; }
    .wrap { width:min(90vw,720px); background:#151925; border:1px solid #2a3145; border-radius:18px; padding:24px; }
    audio { width:100%; }
  </style>
</head>
<body>
  <div class="wrap">
    <h2>{{safeTitle}}</h2>
    <audio controls autoplay src="{{previewUrl}}"></audio>
  </div>
</body>
</html>
""", "text/html; charset=utf-8");
        }

        return Redirect(previewUrl);
    }

    private async Task<object> BuildJobResponseAsync(Guid jobId, string userId, CancellationToken ct)
    {
        var job = await _db.TranscriptionJobs
            .AsNoTracking()
            .Include(x => x.Outputs)
            .FirstAsync(x => x.Id == jobId && x.UserId == userId, ct);

        return ToJobResponse(job);
    }

    private object ToJobResponse(TranscriptionJob job)
    {
        var diagnosticsSnapshot = ReadJobDiagnostics(job);
        var qualitySummary = ParseJsonObject(job.QualitySummaryJson);
        var translationStatuses = ParseJsonObject(job.TranslationStatusesJson);
        var capabilityProfile = ParseJsonDictionary(job.CapabilityProfileJson);
        var contextHints = ParseJsonObject(job.ContextHintsJson);
        var renderPreviewPath = job.Outputs.FirstOrDefault(x => string.Equals(x.OutputType, "render_preview", StringComparison.OrdinalIgnoreCase))?.FilePath;
        var sceneMapPath = job.Outputs.FirstOrDefault(x => string.Equals(x.OutputType, "scene_map", StringComparison.OrdinalIgnoreCase))?.FilePath
            ?? ResolveRootArtifactPath(job, "scene_map.json");
        var speakerMapPath = job.Outputs.FirstOrDefault(x => string.Equals(x.OutputType, "speaker_map", StringComparison.OrdinalIgnoreCase))?.FilePath;
        var lyricAlignmentPath = job.Outputs.FirstOrDefault(x => string.Equals(x.OutputType, "lyric_alignment", StringComparison.OrdinalIgnoreCase))?.FilePath;
        var timeoutProfileApplied = job.QualityProfile;
        if (capabilityProfile is not null)
        {
            timeoutProfileApplied = ReadCapabilityString(capabilityProfile, "timeoutProfileApplied") ?? timeoutProfileApplied;
        }
        var previewModeApplied = diagnosticsSnapshot.PreviewModeApplied;
        var shouldPreferRenderedPreview =
            !string.IsNullOrWhiteSpace(renderPreviewPath) &&
            (string.Equals(job.RenderedPreviewMode, "rendered", StringComparison.OrdinalIgnoreCase) ||
             string.Equals(job.ContentMode, "anime_song", StringComparison.OrdinalIgnoreCase) ||
             !string.Equals(job.KaraokeGranularity, "off", StringComparison.OrdinalIgnoreCase) ||
             string.Equals(job.SpeakerStyleMode, "advanced", StringComparison.OrdinalIgnoreCase));
        if (shouldPreferRenderedPreview)
        {
            previewModeApplied = "rendered";
        }
        else if (string.IsNullOrWhiteSpace(previewModeApplied))
        {
            previewModeApplied = !string.IsNullOrWhiteSpace(renderPreviewPath) ? "rendered" : "fast";
        }

        return new
        {
            job.Id,
            job.SourceType,
            SourceValue = ToClientSourceValue(job.SourceType, job.SourceValue),
            job.Model,
            job.Task,
            job.Language,
            job.OutputFormat,
            requestedOutputs = ParseStringList(job.RequestedOutputsJson, BuildRequestedOutputs(job.OutputFormat, job.BurnSubtitlesIntoVideo, job.AiEnhancementEnabled, job.AiMode)),
            job.DeliveryMode,
            job.GenerateSubtitles,
            job.BurnSubtitlesIntoVideo,
            job.KeepTimestamps,
            job.SplitBySentence,
            job.WordTimestamps,
            job.VadFilter,
            job.DevicePreference,
            job.ComputeType,
            job.BeamSize,
            job.MaxSubtitleChars,
            job.SubtitleStyle,
            targetLanguages = ParseStringList(job.TargetLanguagesJson),
            job.VideoDeliveryMode,
            job.AiEnhancementEnabled,
            job.AiProvider,
            job.AiModel,
            job.AiMode,
            job.AiPrompt,
            job.AiTemperature,
            job.AiTopP,
            job.AiMaxTokens,
            job.AiChunkChars,
            job.AiUseVisualContext,
            job.AiFrameSampleSeconds,
            job.PreserveTimestamps,
            job.AiRevisionPasses,
            job.UseAdvancedAlignment,
            job.EnableOnlineContext,
            contextHints,
            job.QualityProfile,
            job.ContentMode,
            job.SpeakerStyleMode,
            job.StyleIntensity,
            job.RenderedPreviewMode,
            job.AnimeSongLayoutMode,
            job.KaraokeGranularity,
            job.Status,
            job.ProgressPercent,
            job.CurrentStage,
            job.CurrentPass,
            job.TotalPasses,
            job.ErrorMessage,
            styleSource = job.StyleSource ?? diagnosticsSnapshot.StyleSource,
            detectedContentType = job.DetectedContentType,
            contentDetectionConfidence = job.ContentDetectionConfidence,
            speakerModeApplied = job.SpeakerModeApplied,
            karaokeModeApplied = job.KaraokeModeApplied,
            renderPreviewPath,
            sceneMapPath,
            speakerMapPath,
            lyricAlignmentPath,
            voiceAnalysisSource = diagnosticsSnapshot.VoiceAnalysisSource,
            sceneAnalysisSource = diagnosticsSnapshot.SceneAnalysisSource,
            previewModeApplied,
            plannerModelUsed = diagnosticsSnapshot.PlannerModelUsed,
            reviewModelUsed = diagnosticsSnapshot.ReviewModelUsed,
            requestedAiProvider = job.AiEnhancementEnabled ? (diagnosticsSnapshot.RequestedAiProvider ?? job.AiProvider) : null,
            requestedAiModel = job.AiEnhancementEnabled ? (diagnosticsSnapshot.RequestedAiModel ?? job.AiModel) : null,
            effectiveAiProvider = job.AiEnhancementEnabled
                ? (diagnosticsSnapshot.EffectiveAiProvider ?? diagnosticsSnapshot.RequestedAiProvider ?? job.AiProvider)
                : null,
            effectiveAiModel = job.AiEnhancementEnabled
                ? (diagnosticsSnapshot.EffectiveAiModel ?? diagnosticsSnapshot.RequestedAiModel ?? job.AiModel)
                : null,
            runtimeTarget = job.AiEnhancementEnabled ? diagnosticsSnapshot.RuntimeTarget : null,
            modelInstalledAtSubmission = job.AiEnhancementEnabled ? diagnosticsSnapshot.ModelInstalledAtSubmission : null,
            qualitySummary,
            translationStatuses,
            capabilityProfile,
            timeoutProfileApplied,
            jobTimeoutMinutes = _pythonSettings.TimeoutMinutes,
            structuredTimeoutSeconds = ReadCapabilityInt(capabilityProfile, "structuredTimeoutSeconds"),
            styleTimeoutSeconds = ReadCapabilityInt(capabilityProfile, "styleTimeoutSeconds"),
            sourceDurationSeconds = diagnosticsSnapshot.SourceDurationSeconds ?? job.DurationSeconds,
            outputDurationSeconds = diagnosticsSnapshot.OutputDurationSeconds,
            musicalSegmentDurations = diagnosticsSnapshot.MusicalSegmentDurations,
            fallbacks = diagnosticsSnapshot.Fallbacks,
            diagnostics = diagnosticsSnapshot.Diagnostics,
            job.LanguageDetected,
            job.DurationSeconds,
            job.CreatedAtUtc,
            job.StartedAtUtc,
            job.FinishedAtUtc,
            outputs = job.Outputs
                .OrderBy(x => x.CreatedAtUtc)
                .Where(x => !IsHiddenOutputType(x.OutputType))
                .Select(ToOutputResponse)
                .ToList()
        };
    }

    private JobDiagnosticsSnapshot ReadJobDiagnostics(TranscriptionJob job)
    {
        var diagnosticsOutput = job.Outputs
            .OrderByDescending(x => x.CreatedAtUtc)
            .FirstOrDefault(x => string.Equals(x.OutputType, "job_diagnostics", StringComparison.OrdinalIgnoreCase));

        if (diagnosticsOutput is null || string.IsNullOrWhiteSpace(diagnosticsOutput.FilePath))
        {
            return JobDiagnosticsSnapshot.Empty;
        }

        try
        {
            var absolutePath = _storage.ResolveManagedFilePath(diagnosticsOutput.FilePath);
            if (!System.IO.File.Exists(absolutePath))
            {
                return JobDiagnosticsSnapshot.Empty;
            }

            using var document = JsonDocument.Parse(System.IO.File.ReadAllText(absolutePath));
            var diagnostics = new List<object>();
            string? styleSource = null;
            string? voiceAnalysisSource = null;
            string? sceneAnalysisSource = null;
            string? previewModeApplied = null;
            string? plannerModelUsed = null;
            string? reviewModelUsed = null;
            string? requestedAiProvider = null;
            string? requestedAiModel = null;
            string? effectiveAiProvider = null;
            string? effectiveAiModel = null;
            string? runtimeTarget = null;
            bool? modelInstalledAtSubmission = null;
            double? sourceDurationSeconds = null;
            double? outputDurationSeconds = null;
            var musicalSegmentDurations = new List<object>();
            var fallbacks = new List<object>();

            if (document.RootElement.TryGetProperty("styleSource", out var styleSourceElement) &&
                styleSourceElement.ValueKind == JsonValueKind.String)
            {
                styleSource = styleSourceElement.GetString();
            }

            if (document.RootElement.TryGetProperty("voiceAnalysisSource", out var voiceAnalysisSourceElement) &&
                voiceAnalysisSourceElement.ValueKind == JsonValueKind.String)
            {
                voiceAnalysisSource = voiceAnalysisSourceElement.GetString();
            }

            if (document.RootElement.TryGetProperty("sceneAnalysisSource", out var sceneAnalysisSourceElement) &&
                sceneAnalysisSourceElement.ValueKind == JsonValueKind.String)
            {
                sceneAnalysisSource = sceneAnalysisSourceElement.GetString();
            }

            if (document.RootElement.TryGetProperty("previewModeApplied", out var previewModeAppliedElement) &&
                previewModeAppliedElement.ValueKind == JsonValueKind.String)
            {
                previewModeApplied = previewModeAppliedElement.GetString();
            }

            if (document.RootElement.TryGetProperty("plannerModelUsed", out var plannerModelUsedElement) &&
                plannerModelUsedElement.ValueKind == JsonValueKind.String)
            {
                plannerModelUsed = plannerModelUsedElement.GetString();
            }

            if (document.RootElement.TryGetProperty("reviewModelUsed", out var reviewModelUsedElement) &&
                reviewModelUsedElement.ValueKind == JsonValueKind.String)
            {
                reviewModelUsed = reviewModelUsedElement.GetString();
            }

            if (document.RootElement.TryGetProperty("requestedAiProvider", out var requestedAiProviderElement) &&
                requestedAiProviderElement.ValueKind == JsonValueKind.String)
            {
                requestedAiProvider = requestedAiProviderElement.GetString();
            }

            if (document.RootElement.TryGetProperty("requestedAiModel", out var requestedAiModelElement) &&
                requestedAiModelElement.ValueKind == JsonValueKind.String)
            {
                requestedAiModel = requestedAiModelElement.GetString();
            }

            if (document.RootElement.TryGetProperty("effectiveAiProvider", out var effectiveAiProviderElement) &&
                effectiveAiProviderElement.ValueKind == JsonValueKind.String)
            {
                effectiveAiProvider = effectiveAiProviderElement.GetString();
            }

            if (document.RootElement.TryGetProperty("effectiveAiModel", out var effectiveAiModelElement) &&
                effectiveAiModelElement.ValueKind == JsonValueKind.String)
            {
                effectiveAiModel = effectiveAiModelElement.GetString();
            }

            if (document.RootElement.TryGetProperty("runtimeTarget", out var runtimeTargetElement) &&
                runtimeTargetElement.ValueKind == JsonValueKind.String)
            {
                runtimeTarget = runtimeTargetElement.GetString();
            }

            if (document.RootElement.TryGetProperty("modelInstalledAtSubmission", out var modelInstalledAtSubmissionElement) &&
                (modelInstalledAtSubmissionElement.ValueKind == JsonValueKind.True ||
                 modelInstalledAtSubmissionElement.ValueKind == JsonValueKind.False))
            {
                modelInstalledAtSubmission = modelInstalledAtSubmissionElement.GetBoolean();
            }

            if (document.RootElement.TryGetProperty("sourceDurationSeconds", out var sourceDurationSecondsElement) &&
                sourceDurationSecondsElement.ValueKind == JsonValueKind.Number &&
                sourceDurationSecondsElement.TryGetDouble(out var parsedSourceDuration))
            {
                sourceDurationSeconds = parsedSourceDuration;
            }

            if (document.RootElement.TryGetProperty("outputDurationSeconds", out var outputDurationSecondsElement) &&
                outputDurationSecondsElement.ValueKind == JsonValueKind.Number &&
                outputDurationSecondsElement.TryGetDouble(out var parsedOutputDuration))
            {
                outputDurationSeconds = parsedOutputDuration;
            }

            if (document.RootElement.TryGetProperty("musicalSegmentDurations", out var musicalSegmentDurationsElement) &&
                musicalSegmentDurationsElement.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in musicalSegmentDurationsElement.EnumerateArray())
                {
                    musicalSegmentDurations.Add(JsonSerializer.Deserialize<object>(item.GetRawText(), JsonOptions)!);
                }
            }

            if (document.RootElement.TryGetProperty("fallbacks", out var fallbacksElement) &&
                fallbacksElement.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in fallbacksElement.EnumerateArray())
                {
                    fallbacks.Add(JsonSerializer.Deserialize<object>(item.GetRawText(), JsonOptions)!);
                }
            }

            if (document.RootElement.TryGetProperty("diagnostics", out var diagnosticsElement) &&
                diagnosticsElement.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in diagnosticsElement.EnumerateArray())
                {
                    if (item.ValueKind != JsonValueKind.Object)
                        continue;

                    diagnostics.Add(new
                    {
                        stage = ReadJsonString(item, "stage"),
                        severity = ReadJsonString(item, "severity"),
                        message = ReadJsonString(item, "message"),
                        model = ReadJsonString(item, "model"),
                        language = ReadJsonString(item, "language"),
                        fallbackUsed = ReadJsonString(item, "fallbackUsed"),
                        rawExcerpt = ReadJsonString(item, "rawExcerpt"),
                        sourceField = ReadJsonString(item, "sourceField"),
                        durationMs = ReadJsonInt(item, "durationMs")
                    });
                }
            }

            return new JobDiagnosticsSnapshot(
                styleSource,
                voiceAnalysisSource,
                sceneAnalysisSource,
                previewModeApplied,
                plannerModelUsed,
                reviewModelUsed,
                requestedAiProvider,
                requestedAiModel,
                effectiveAiProvider,
                effectiveAiModel,
                runtimeTarget,
                modelInstalledAtSubmission,
                sourceDurationSeconds,
                outputDurationSeconds,
                musicalSegmentDurations,
                fallbacks,
                diagnostics);
        }
        catch
        {
            return JobDiagnosticsSnapshot.Empty;
        }
    }

    private string? ResolveRootArtifactPath(TranscriptionJob job, string fileName)
    {
        var anchor = job.Outputs
            .OrderByDescending(x => x.CreatedAtUtc)
            .Select(x => x.FilePath)
            .FirstOrDefault(x => !string.IsNullOrWhiteSpace(x) &&
                !x!.Contains("/translations/", StringComparison.OrdinalIgnoreCase) &&
                !x.Contains("\\translations\\", StringComparison.OrdinalIgnoreCase) &&
                !x.Contains("/enhanced/", StringComparison.OrdinalIgnoreCase) &&
                !x.Contains("\\enhanced\\", StringComparison.OrdinalIgnoreCase));

        if (string.IsNullOrWhiteSpace(anchor))
            return null;

        var directory = Path.GetDirectoryName(anchor);
        if (string.IsNullOrWhiteSpace(directory))
            return null;

        var candidate = Path.Combine(directory, fileName).Replace("\\", "/");
        var absolutePath = _storage.ResolveManagedFilePath(candidate);
        return System.IO.File.Exists(absolutePath) ? candidate : null;
    }

    private object ToPreferenceResponse(UserTranscriptionPreference preference)
    {
        var task = NormalizeValue(preference.Task, AllowedTasks, "transcribe");
        var aiMode = NormalizeAiModeCsv(preference.AiMode, task);
        var targetLanguages = task == "translate"
            ? NormalizeTargetLanguages(ParseStringList(preference.TargetLanguagesJson))
            : [];
        var burnSubtitlesIntoVideo = ResolveBurnSubtitlesIntoVideo(preference.BurnSubtitlesIntoVideo, task, targetLanguages);
        var requestedOutputs = NormalizeRequestedOutputs(
            ParseStringList(preference.RequestedOutputsJson, ["srt"]),
            preference.OutputFormat,
            burnSubtitlesIntoVideo,
            preference.AiEnhancementEnabled,
            aiMode);
        var subtitleStyle = NormalizeValue(preference.SubtitleStyle, AllowedSubtitleStyles, "default");

        return new
        {
            sourceTypeDefault = NormalizeSourceType(preference.SourceTypeDefault, fallback: "file_path"),
            model = NormalizeValue(preference.Model, AllowedModels, "large-v3"),
            task,
            language = NormalizeValue(preference.Language, AllowedLanguages, "auto"),
            outputFormat = NormalizeOutputFormat(preference.OutputFormat, requestedOutputs, burnSubtitlesIntoVideo),
            requestedOutputs,
            deliveryMode = NormalizeValue(preference.DeliveryMode, AllowedVideoDeliveryModes, "standard"),
            generateSubtitles = preference.GenerateSubtitles,
            burnSubtitlesIntoVideo,
            keepTimestamps = preference.KeepTimestamps,
            splitBySentence = preference.SplitBySentence,
            wordTimestamps = preference.WordTimestamps,
            vadFilter = preference.VadFilter,
            devicePreference = NormalizeValue(preference.DevicePreference, AllowedDevices, "auto"),
            computeType = NormalizeValue(preference.ComputeType, AllowedComputeTypes, "float16"),
            beamSize = preference.BeamSize <= 0 ? 5 : preference.BeamSize,
            maxSubtitleChars = preference.MaxSubtitleChars,
            subtitleStyle,
            subtitleVisualPreset = subtitleStyle,
            targetLanguages,
            videoDeliveryMode = NormalizeVideoDeliveryMode(preference.VideoDeliveryMode, task, targetLanguages, burnSubtitlesIntoVideo),
            aiEnhancementEnabled = preference.AiEnhancementEnabled,
            aiProvider = NormalizeAiProvider(preference.AiProvider),
            aiModel = NormalizeAiModel(preference.AiModel),
            aiMode,
            aiPrompt = string.IsNullOrWhiteSpace(preference.AiPrompt) ? null : preference.AiPrompt,
            aiTemperature = preference.AiTemperature ?? 0.2,
            aiTopP = preference.AiTopP ?? 0.9,
            aiMaxTokens = preference.AiMaxTokens ?? 1024,
            aiChunkChars = preference.AiChunkChars ?? 6000,
            aiUseVisualContext = preference.AiUseVisualContext,
            aiFrameSampleSeconds = preference.AiFrameSampleSeconds ?? 12,
            preserveTimestamps = preference.PreserveTimestamps,
            aiRevisionPasses = preference.AiRevisionPasses <= 0 ? 3 : preference.AiRevisionPasses,
            useAdvancedAlignment = NormalizeValue(preference.UseAdvancedAlignment, AllowedAlignmentModes, "auto"),
            enableOnlineContext = preference.EnableOnlineContext,
            contextHints = ParseJsonObject(preference.ContextHintsJson),
            qualityProfile = NormalizeValue(preference.QualityProfile, AllowedQualityProfiles, "balanced"),
            contentMode = NormalizeValue(preference.ContentMode, AllowedContentModes, "episode"),
            speakerStyleMode = NormalizeValue(preference.SpeakerStyleMode, AllowedSpeakerStyleModes, "heuristic"),
            styleIntensity = NormalizeValue(preference.StyleIntensity, AllowedStyleIntensities, "thematic"),
            renderedPreviewMode = NormalizeValue(preference.RenderedPreviewMode, AllowedRenderedPreviewModes, "fast"),
            animeSongLayoutMode = NormalizeValue(preference.AnimeSongLayoutMode, AllowedAnimeSongLayoutModes, "off"),
            karaokeGranularity = NormalizeKaraokeGranularity(preference.KaraokeGranularity, preference.ContentMode)
        };
    }

    private object BuildDefaultPreferencesResponse()
    {
        return new
        {
            sourceTypeDefault = "file_path",
            model = "large-v3",
            task = "transcribe",
            language = "auto",
            outputFormat = "srt",
            requestedOutputs = new[] { "srt" },
            deliveryMode = "standard",
            generateSubtitles = true,
            burnSubtitlesIntoVideo = false,
            keepTimestamps = true,
            splitBySentence = true,
            wordTimestamps = false,
            vadFilter = true,
            devicePreference = "auto",
            computeType = "float16",
            beamSize = 5,
            maxSubtitleChars = 42,
            subtitleStyle = "default",
            subtitleVisualPreset = "default",
            targetLanguages = Array.Empty<string>(),
            videoDeliveryMode = "standard",
            aiEnhancementEnabled = false,
            aiProvider = "ollama_project",
            aiModel = "qwen2.5vl:7b",
            aiMode = "correction",
            aiPrompt = (string?)null,
            aiTemperature = 0.2,
            aiTopP = 0.9,
            aiMaxTokens = 1024,
            aiChunkChars = 6000,
            aiUseVisualContext = false,
            aiFrameSampleSeconds = 12,
            preserveTimestamps = true,
            aiRevisionPasses = 3,
            useAdvancedAlignment = "auto",
            enableOnlineContext = false,
            contextHints = (object?)null,
            qualityProfile = "balanced",
            contentMode = "episode",
            speakerStyleMode = "heuristic",
            styleIntensity = "thematic",
            renderedPreviewMode = "fast",
            animeSongLayoutMode = "off",
            karaokeGranularity = "off"
        };
    }

    private void ApplyPreferenceRequest(UserTranscriptionPreference preference, SaveTranscriptionPreferencesRequest request)
    {
        var task = NormalizeValue(request.Task, AllowedTasks, "transcribe");
        var aiMode = NormalizeAiModeCsv(request.AiMode, task);
        var aiEnhancementEnabled = request.AiEnhancementEnabled;
        var targetLanguages = task == "translate" ? NormalizeTargetLanguages(request.TargetLanguages) : [];
        var burnSubtitlesIntoVideo = ResolveBurnSubtitlesIntoVideo(request.BurnSubtitlesIntoVideo, task, targetLanguages);
        var requestedOutputs = NormalizeRequestedOutputs(request.RequestedOutputs, request.OutputFormat, burnSubtitlesIntoVideo, aiEnhancementEnabled, aiMode);
        var subtitleStyle = NormalizeValue(request.SubtitleVisualPreset ?? request.SubtitleStyle, AllowedSubtitleStyles, "default");

        preference.SourceTypeDefault = NormalizeSourceType(request.SourceTypeDefault, fallback: "file_path");
        preference.Model = NormalizeValue(request.Model, AllowedModels, "large-v3");
        preference.Task = task;
        preference.Language = NormalizeValue(request.Language, AllowedLanguages, "auto");
        preference.OutputFormat = NormalizeOutputFormat(request.OutputFormat, requestedOutputs, burnSubtitlesIntoVideo);
        preference.RequestedOutputsJson = SerializeStringList(requestedOutputs);
        preference.DeliveryMode = NormalizeValue(request.DeliveryMode, AllowedVideoDeliveryModes, "standard");
        preference.GenerateSubtitles = request.GenerateSubtitles;
        preference.BurnSubtitlesIntoVideo = burnSubtitlesIntoVideo;
        preference.KeepTimestamps = request.KeepTimestamps;
        preference.SplitBySentence = request.SplitBySentence;
        preference.WordTimestamps = request.WordTimestamps;
        preference.VadFilter = request.VadFilter;
        preference.DevicePreference = NormalizeValue(request.DevicePreference, AllowedDevices, "auto");
        preference.ComputeType = NormalizeValue(request.ComputeType, AllowedComputeTypes, "float16");
        preference.BeamSize = request.BeamSize <= 0 ? 5 : request.BeamSize;
        preference.MaxSubtitleChars = request.MaxSubtitleChars;
        preference.SubtitleStyle = subtitleStyle;
        preference.TargetLanguagesJson = SerializeStringList(targetLanguages);
        preference.VideoDeliveryMode = NormalizeVideoDeliveryMode(request.VideoDeliveryMode, task, targetLanguages, burnSubtitlesIntoVideo);
        preference.AiEnhancementEnabled = aiEnhancementEnabled;
        preference.AiProvider = NormalizeAiProvider(request.AiProvider);
        preference.AiModel = NormalizeAiModel(request.AiModel);
        preference.AiMode = aiMode;
        preference.AiPrompt = string.IsNullOrWhiteSpace(request.AiPrompt) ? null : request.AiPrompt.Trim();
        preference.AiTemperature = request.AiTemperature;
        preference.AiTopP = request.AiTopP;
        preference.AiMaxTokens = request.AiMaxTokens;
        preference.AiChunkChars = request.AiChunkChars;
        preference.AiUseVisualContext = request.AiUseVisualContext;
        preference.AiFrameSampleSeconds = request.AiFrameSampleSeconds;
        preference.PreserveTimestamps = request.PreserveTimestamps;
        preference.AiRevisionPasses = Math.Clamp(request.AiRevisionPasses, 0, 10);
        preference.UseAdvancedAlignment = NormalizeValue(request.UseAdvancedAlignment, AllowedAlignmentModes, "auto");
        preference.EnableOnlineContext = request.EnableOnlineContext;
        preference.ContextHintsJson = SerializeJsonObject(request.ContextHints);
        preference.QualityProfile = NormalizeValue(request.QualityProfile, AllowedQualityProfiles, "balanced");
        preference.ContentMode = NormalizeValue(request.ContentMode, AllowedContentModes, "episode");
        preference.SpeakerStyleMode = NormalizeValue(request.SpeakerStyleMode, AllowedSpeakerStyleModes, "heuristic");
        preference.StyleIntensity = NormalizeValue(request.StyleIntensity, AllowedStyleIntensities, "thematic");
        preference.RenderedPreviewMode = NormalizeValue(request.RenderedPreviewMode, AllowedRenderedPreviewModes, "fast");
        preference.AnimeSongLayoutMode = NormalizeValue(request.AnimeSongLayoutMode, AllowedAnimeSongLayoutModes, "off");
        preference.KaraokeGranularity = NormalizeKaraokeGranularity(request.KaraokeGranularity, request.ContentMode);
    }

    private TranscriptionJob BuildJobFromRequest(string userId, string sourceType, string sourceValue, CreateTranscriptionJobRequest request)
    {
        var task = NormalizeValue(request.Task, AllowedTasks, "transcribe");
        var aiMode = NormalizeAiModeCsv(request.AiMode, task);
        var aiEnhancementEnabled = request.AiEnhancementEnabled;
        var targetLanguages = task == "translate" ? NormalizeTargetLanguages(request.TargetLanguages) : [];
        var burnSubtitlesIntoVideo = ResolveBurnSubtitlesIntoVideo(request.BurnSubtitlesIntoVideo, task, targetLanguages);
        var requestedOutputs = NormalizeRequestedOutputs(request.RequestedOutputs, request.OutputFormat, burnSubtitlesIntoVideo, aiEnhancementEnabled, aiMode);
        var subtitleStyle = NormalizeValue(request.SubtitleVisualPreset ?? request.SubtitleStyle, AllowedSubtitleStyles, "default");

        return new TranscriptionJob
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            SourceType = sourceType,
            SourceValue = sourceValue,
            Model = NormalizeValue(request.Model, AllowedModels, "large-v3"),
            Task = task,
            Language = NormalizeValue(request.Language, AllowedLanguages, "auto"),
            OutputFormat = NormalizeOutputFormat(request.OutputFormat, requestedOutputs, burnSubtitlesIntoVideo),
            RequestedOutputsJson = SerializeStringList(requestedOutputs),
            DeliveryMode = NormalizeValue(request.DeliveryMode, AllowedVideoDeliveryModes, "standard"),
            GenerateSubtitles = request.GenerateSubtitles,
            BurnSubtitlesIntoVideo = burnSubtitlesIntoVideo,
            KeepTimestamps = request.KeepTimestamps,
            SplitBySentence = request.SplitBySentence,
            WordTimestamps = request.WordTimestamps,
            VadFilter = request.VadFilter,
            DevicePreference = NormalizeValue(request.DevicePreference, AllowedDevices, "auto"),
            ComputeType = NormalizeValue(request.ComputeType, AllowedComputeTypes, "float16"),
            BeamSize = request.BeamSize <= 0 ? 5 : request.BeamSize,
            MaxSubtitleChars = request.MaxSubtitleChars,
            SubtitleStyle = subtitleStyle,
            TargetLanguagesJson = SerializeStringList(targetLanguages),
            VideoDeliveryMode = NormalizeVideoDeliveryMode(request.VideoDeliveryMode, task, targetLanguages, burnSubtitlesIntoVideo),
            AiEnhancementEnabled = aiEnhancementEnabled,
            AiProvider = NormalizeAiProvider(request.AiProvider),
            AiModel = NormalizeAiModel(request.AiModel),
            AiMode = aiMode,
            AiPrompt = string.IsNullOrWhiteSpace(request.AiPrompt) ? null : request.AiPrompt.Trim(),
            AiTemperature = request.AiTemperature,
            AiTopP = request.AiTopP,
            AiMaxTokens = request.AiMaxTokens,
            AiChunkChars = request.AiChunkChars,
            AiUseVisualContext = request.AiUseVisualContext,
            AiFrameSampleSeconds = request.AiFrameSampleSeconds,
            PreserveTimestamps = request.PreserveTimestamps,
            AiRevisionPasses = Math.Clamp(request.AiRevisionPasses, 0, 10),
            UseAdvancedAlignment = NormalizeValue(request.UseAdvancedAlignment, AllowedAlignmentModes, "auto"),
            EnableOnlineContext = request.EnableOnlineContext,
            ContextHintsJson = SerializeJsonObject(request.ContextHints),
            QualityProfile = NormalizeValue(request.QualityProfile, AllowedQualityProfiles, "balanced"),
            ContentMode = NormalizeValue(request.ContentMode, AllowedContentModes, "episode"),
            SpeakerStyleMode = NormalizeValue(request.SpeakerStyleMode, AllowedSpeakerStyleModes, "heuristic"),
            StyleIntensity = NormalizeValue(request.StyleIntensity, AllowedStyleIntensities, "thematic"),
            RenderedPreviewMode = NormalizeValue(request.RenderedPreviewMode, AllowedRenderedPreviewModes, "fast"),
            AnimeSongLayoutMode = NormalizeValue(request.AnimeSongLayoutMode, AllowedAnimeSongLayoutModes, "off"),
            KaraokeGranularity = NormalizeKaraokeGranularity(request.KaraokeGranularity, request.ContentMode),
            Status = "pending",
            ProgressPercent = 0,
            CurrentStage = "pending",
            CurrentPass = 0,
            TotalPasses = Math.Clamp(request.AiRevisionPasses, 0, 10),
            CreatedAtUtc = DateTime.UtcNow
        };
    }

    private TranscriptionJob BuildJobFromUpload(string userId, string relativePath, CreateTranscriptionUploadRequest request)
    {
        var createRequest = new CreateTranscriptionJobRequest
        {
            SourceType = "file_path",
            SourceValue = relativePath,
            Model = request.Model,
            Task = request.Task,
            Language = request.Language,
            OutputFormat = request.OutputFormat,
            RequestedOutputs = ParseStringList(request.RequestedOutputsJson, ParseCsv(request.RequestedOutputsCsv)),
            DeliveryMode = request.DeliveryMode,
            GenerateSubtitles = request.GenerateSubtitles,
            BurnSubtitlesIntoVideo = request.BurnSubtitlesIntoVideo,
            KeepTimestamps = request.KeepTimestamps,
            SplitBySentence = request.SplitBySentence,
            WordTimestamps = request.WordTimestamps,
            VadFilter = request.VadFilter,
            DevicePreference = request.DevicePreference,
            ComputeType = request.ComputeType,
            BeamSize = request.BeamSize,
            MaxSubtitleChars = request.MaxSubtitleChars,
            SubtitleStyle = request.SubtitleStyle,
            SubtitleVisualPreset = request.SubtitleVisualPreset,
            TargetLanguages = ParseStringList(request.TargetLanguagesJson, ParseCsv(request.TargetLanguagesCsv)),
            VideoDeliveryMode = request.VideoDeliveryMode,
            AiEnhancementEnabled = request.AiEnhancementEnabled,
            AiProvider = request.AiProvider,
            AiModel = request.AiModel,
            AiMode = request.AiMode,
            AiPrompt = request.AiPrompt,
            AiTemperature = request.AiTemperature,
            AiTopP = request.AiTopP,
            AiMaxTokens = request.AiMaxTokens,
            AiChunkChars = request.AiChunkChars,
            AiUseVisualContext = request.AiUseVisualContext,
            AiFrameSampleSeconds = request.AiFrameSampleSeconds,
            PreserveTimestamps = request.PreserveTimestamps,
            AiRevisionPasses = request.AiRevisionPasses,
            UseAdvancedAlignment = request.UseAdvancedAlignment,
            EnableOnlineContext = request.EnableOnlineContext,
            ContextHints = ParseJsonObject(request.ContextHintsJson),
            QualityProfile = request.QualityProfile,
            ContentMode = request.ContentMode,
            SpeakerStyleMode = request.SpeakerStyleMode,
            StyleIntensity = request.StyleIntensity,
            RenderedPreviewMode = request.RenderedPreviewMode,
            AnimeSongLayoutMode = request.AnimeSongLayoutMode,
            KaraokeGranularity = request.KaraokeGranularity
        };

        return BuildJobFromRequest(userId, "file_path", relativePath, createRequest);
    }

    private async Task<string?> ValidateAiRuntimeSelectionAsync(
        bool aiEnhancementEnabled,
        string? aiProvider,
        string? aiModel,
        CancellationToken ct)
    {
        if (!aiEnhancementEnabled)
        {
            return null;
        }

        var provider = NormalizeAiProvider(aiProvider);
        var model = NormalizeAiModel(aiModel);
        if (string.IsNullOrWhiteSpace(model))
        {
            return "Selecione um modelo multimodal de IA.";
        }

        var capabilities = await _pythonClient.GetCapabilitiesAsync(ct);
        var providers = capabilities.Providers ?? [];
        var providerEntry = providers.FirstOrDefault(entry =>
            string.Equals(ReadCapabilityString(entry, "id"), provider, StringComparison.OrdinalIgnoreCase));

        if (providerEntry is null || !ReadCapabilityBool(providerEntry, "available"))
        {
            return $"O provider '{provider}' não está disponível no runtime ativo.";
        }

        var allowedMultimodal = ReadCapabilityStringList(providerEntry, "multimodalModels");
        if (!allowedMultimodal.Contains(model, StringComparer.OrdinalIgnoreCase))
        {
            return $"O modelo '{model}' não faz parte do catálogo multimodal público do provider '{provider}'.";
        }

        var installedByProvider = ReadCapabilityStringDictionaryOfLists(capabilities.InstalledModelsByProvider);
        if (!installedByProvider.TryGetValue(provider, out var installedModels) ||
            !installedModels.Contains(model, StringComparer.OrdinalIgnoreCase))
        {
            return $"O modelo '{model}' não está instalado para o provider '{provider}'. Baixe o modelo antes de rodar.";
        }

        return null;
    }

    private async Task<TranscriptionJobOutput?> GetOwnedOutputAsync(Guid outputId, CancellationToken ct)
    {
        var userId = GetUserId();
        return await _db.TranscriptionJobOutputs
            .AsNoTracking()
            .Include(x => x.Job)
            .FirstOrDefaultAsync(x => x.Id == outputId && x.Job != null && x.Job.UserId == userId, ct);
    }

    private object ToOutputResponse(TranscriptionJobOutput output)
    {
        var previewKind = GetPreviewKind(output);
        var canPreviewInline = previewKind is "text" or "video" or "audio";
        var downloadUrl = Url.Action(nameof(DownloadOutput), new { id = output.Id }) ?? $"/api/transcription/outputs/{output.Id}/download";
        var previewUrl = Url.Action(nameof(PreviewOutput), new { id = output.Id }) ?? $"/api/transcription/outputs/{output.Id}/preview";
        var previewPageUrl = Url.Action(nameof(PreviewPage), new { id = output.Id }) ?? $"/api/transcription/outputs/{output.Id}/preview-page";

        var fileName = BuildDownloadFileName(output);
        var contentType = GetOutputContentType(output.OutputType);

        return new
        {
            output.Id,
            output.OutputType,
            output.FilePath,
            output.ContentText,
            output.CreatedAtUtc,
            hasTextContent = !string.IsNullOrWhiteSpace(output.ContentText),
            contentLength = string.IsNullOrWhiteSpace(output.ContentText) ? (int?)null : output.ContentText.Length,
            fileName,
            contentType,
            canPreviewInline,
            previewKind,
            previewUrl,
            previewPageUrl,
            downloadUrl
        };
    }

    private static bool IsHiddenOutputType(string? outputType)
        => string.Equals(outputType, "job_diagnostics", StringComparison.OrdinalIgnoreCase)
        || string.Equals(outputType, "quality_report", StringComparison.OrdinalIgnoreCase)
        || string.Equals(outputType, "style_map", StringComparison.OrdinalIgnoreCase)
        || string.Equals(outputType, "alignment_report", StringComparison.OrdinalIgnoreCase)
        || string.Equals(outputType, "scene_map", StringComparison.OrdinalIgnoreCase)
        || string.Equals(outputType, "speaker_map", StringComparison.OrdinalIgnoreCase)
        || string.Equals(outputType, "lyric_alignment", StringComparison.OrdinalIgnoreCase);

    private static string? ReadJsonString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property))
            return null;

        return property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : property.ToString();
    }

    private static int? ReadJsonInt(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property))
            return null;

        if (property.ValueKind == JsonValueKind.Number && property.TryGetInt32(out var value))
            return value;

        return null;
    }

    private static string GetPreviewKind(TranscriptionJobOutput output)
    {
        var type = (output.OutputType ?? string.Empty).Trim().ToLowerInvariant();
        if (!string.IsNullOrWhiteSpace(output.ContentText)) return "text";
        if (type.Contains("video")) return "video";
        if (type.Contains("audio")) return "audio";

        var extension = Path.GetExtension(output.FilePath ?? string.Empty).TrimStart('.').ToLowerInvariant();
        return extension switch
        {
            "txt" or "srt" or "vtt" or "ass" or "json" => "text",
            "mp4" or "mkv" or "mov" or "avi" or "webm" => "video",
            "mp3" or "wav" or "m4a" or "aac" or "ogg" or "flac" => "audio",
            _ => "binary"
        };
    }

    private static string GetOutputContentType(string? outputType)
    {
        var normalized = (outputType ?? string.Empty).Trim().ToLowerInvariant();
        if (normalized is "text" or "txt" ||
            normalized.Contains("_text_") ||
            normalized.EndsWith("_text") ||
            normalized.Contains("_txt_") ||
            normalized.EndsWith("_txt"))
            return "text/plain; charset=utf-8";
        if (normalized is "srt" || normalized.Contains("_srt_") || normalized.EndsWith("_srt"))
            return "text/plain; charset=utf-8";
        if (normalized is "vtt" || normalized.Contains("_vtt_") || normalized.EndsWith("_vtt"))
            return "text/vtt; charset=utf-8";
        if (normalized is "ass" || normalized.Contains("_ass_") || normalized.EndsWith("_ass"))
            return "text/plain; charset=utf-8";

        return normalized switch
        {
            "translations_manifest" or "job_diagnostics" => "application/json; charset=utf-8",
            "karaoke_plan" or "scene_map" or "speaker_map" or "lyric_alignment" or "quality_report" or "style_map" or "alignment_report" => "application/json; charset=utf-8",
            "render_preview" => "video/mp4",
            "video_burned" => "video/mp4",
            "video_muxed" => "video/x-matroska",
            _ => "application/octet-stream"
        };
    }

    private static string BuildDownloadFileName(TranscriptionJobOutput output)
    {
        var extension = Path.GetExtension(output.FilePath ?? string.Empty);
        if (string.IsNullOrWhiteSpace(extension))
        {
            extension = output.OutputType?.ToLowerInvariant() switch
            {
                "text" or "txt" => ".txt",
                "srt" => ".srt",
                "vtt" => ".vtt",
                "ass" => ".ass",
                "render_preview" => ".mp4",
                "video_burned" => ".mp4",
                "video_muxed" => ".mkv",
                "translations_manifest" or "job_diagnostics" or "karaoke_plan" or "scene_map" or "speaker_map" or "lyric_alignment" or "quality_report" or "style_map" or "alignment_report" => ".json",
                _ => ".bin"
            };
        }

        var safeType = new string((output.OutputType ?? "output").Where(ch => char.IsLetterOrDigit(ch) || ch is '_' or '-').ToArray());
        if (string.IsNullOrWhiteSpace(safeType)) safeType = "output";
        return $"{safeType}{extension}";
    }

    private string GetUserId()
    {
        return User.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? User.FindFirstValue("sub")
               ?? throw new UnauthorizedAccessException("Usuário autenticado não identificado.");
    }

    private static string NormalizeSourceType(string? value, string fallback = "file_path")
        => NormalizeValue(value, AllowedSourceTypes, fallback);

    private static string NormalizeOutputFormat(string? outputFormat, IReadOnlyCollection<string>? requestedOutputs = null, bool requestVideoBurned = false)
    {
        var normalized = (outputFormat ?? string.Empty).Trim().ToLowerInvariant();
        if (normalized is "txt" or "srt" or "vtt" or "ass" or "all" or "video_only" or "video_burned")
        {
            return normalized;
        }

        var outputs = requestedOutputs ?? [];
        var hasTxt = outputs.Contains("txt", StringComparer.OrdinalIgnoreCase);
        var hasSrt = outputs.Contains("srt", StringComparer.OrdinalIgnoreCase);
        var hasVtt = outputs.Contains("vtt", StringComparer.OrdinalIgnoreCase);
        var hasAss = outputs.Contains("ass", StringComparer.OrdinalIgnoreCase);

        if (requestVideoBurned && !hasTxt && !hasSrt && !hasVtt && !hasAss) return "video_only";
        if (hasTxt && hasSrt && hasVtt) return "all";
        if (hasAss && !hasTxt && !hasSrt && !hasVtt) return "ass";
        if (hasTxt && !hasSrt && !hasVtt) return "txt";
        if (!hasTxt && hasSrt && !hasVtt) return "srt";
        if (!hasTxt && !hasSrt && hasVtt) return "vtt";
        if (outputs.Count > 0) return string.Join('+', outputs);
        return "srt";
    }

    private static string NormalizeValue(string? value, IEnumerable<string> allowed, string fallback)
    {
        var normalized = (value ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(normalized)) return fallback;
        var match = allowed.FirstOrDefault(x => string.Equals(x, normalized, StringComparison.OrdinalIgnoreCase));
        return match ?? fallback;
    }

    private static List<string> BuildRequestedOutputs(string? outputFormat, bool burnSubtitlesIntoVideo, bool aiEnhancementEnabled = false, string? aiMode = null)
    {
        var normalized = (outputFormat ?? string.Empty).Trim().ToLowerInvariant();
        var requested = new List<string>();

        if (normalized == "all")
        {
            requested.AddRange(new[] { "txt", "srt", "vtt" });
        }
        else if (normalized is not "video_only" and not "video_burned")
        {
            foreach (var item in normalized.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                if (item is "txt" or "srt" or "vtt" or "ass")
                    requested.Add(item);
            }

            if (requested.Count == 0)
                requested.Add("srt");
        }

        if (burnSubtitlesIntoVideo || normalized is "video_only" or "video_burned")
            requested.Add("video_burned");

        if (aiEnhancementEnabled && ContainsAiMode(aiMode, "subtitle_styling"))
            requested.Add("ass");

        return requested;
    }

    private static List<string> NormalizeRequestedOutputs(IEnumerable<string>? requestedOutputs, string? outputFormat, bool requestVideoBurned, bool aiEnhancementEnabled = false, string? aiMode = null)
    {
        var values = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (requestedOutputs is not null)
        {
            foreach (var item in requestedOutputs)
            {
                var normalized = (item ?? string.Empty).Trim().ToLowerInvariant();
                if (AllowedTextOutputs.Contains(normalized)) values.Add(normalized);
                if (normalized == "video_burned") values.Add(normalized);
            }
        }

        var normalizedOutputFormat = (outputFormat ?? string.Empty).Trim().ToLowerInvariant();
        if (normalizedOutputFormat == "all")
        {
            values.Add("txt");
            values.Add("srt");
            values.Add("vtt");
        }
        else if (normalizedOutputFormat.Contains('+'))
        {
            foreach (var part in normalizedOutputFormat.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                if (AllowedTextOutputs.Contains(part)) values.Add(part);
            }
        }
        else if (AllowedTextOutputs.Contains(normalizedOutputFormat))
        {
            values.Add(normalizedOutputFormat);
        }

        if (requestVideoBurned || normalizedOutputFormat is "video_only" or "video_burned")
        {
            values.Add("video_burned");
        }

        if (aiEnhancementEnabled && ContainsAiMode(aiMode, "subtitle_styling"))
        {
            values.Add("ass");
        }

        if (values.Count == 0)
        {
            values.Add("srt");
        }

        var ordered = new List<string>();
        foreach (var item in new[] { "txt", "srt", "vtt", "ass", "video_burned" })
        {
            if (values.Contains(item)) ordered.Add(item);
        }
        return ordered;
    }

    private static bool ContainsAiMode(string? raw, string expected)
    {
        return NormalizeAiModeCsv(raw, null)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Contains(expected, StringComparer.OrdinalIgnoreCase);
    }

    private static string NormalizeAiProvider(string? value)
        => NormalizeValue(value, AllowedAiProviders, "ollama_project");

    private static string NormalizeAiModel(string? value)
    {
        var normalized = (value ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(normalized))
            return "qwen2.5vl:7b";

        var matched = AllowedAiModels.FirstOrDefault(x => string.Equals(x, normalized, StringComparison.OrdinalIgnoreCase));
        return matched ?? normalized;
    }

    private static string NormalizeKaraokeGranularity(string? value, string? contentMode)
    {
        var normalizedMode = NormalizeValue(contentMode, AllowedContentModes, "episode");
        var fallback = normalizedMode == "anime_song" ? "syllable" : "off";
        var normalizedValue = NormalizeValue(value, AllowedKaraokeGranularities, fallback);
        if (normalizedMode == "episode")
            return "off";
        return normalizedValue;
    }

    private static bool ShouldForceMuxDelivery(string task, IReadOnlyCollection<string> targetLanguages)
    {
        return string.Equals(task, "translate", StringComparison.OrdinalIgnoreCase) && targetLanguages.Count > 1;
    }

    private static bool ResolveBurnSubtitlesIntoVideo(bool requestVideoBurned, string task, IReadOnlyCollection<string> targetLanguages)
    {
        return ShouldForceMuxDelivery(task, targetLanguages) ? false : requestVideoBurned;
    }

    private static string NormalizeVideoDeliveryMode(string? value, string task, IReadOnlyCollection<string> targetLanguages, bool burnSubtitlesIntoVideo)
    {
        if (ShouldForceMuxDelivery(task, targetLanguages))
            return "mux_subtitles";

        var fallback = burnSubtitlesIntoVideo ? "burned_video" : "standard";
        var normalized = NormalizeValue(value, AllowedVideoDeliveryModes, fallback);

        if (!burnSubtitlesIntoVideo && string.Equals(normalized, "burned_video", StringComparison.OrdinalIgnoreCase))
            return "standard";

        if (burnSubtitlesIntoVideo && string.Equals(normalized, "video_only", StringComparison.OrdinalIgnoreCase))
            return "burned_video";

        return normalized;
    }

    private static List<string> NormalizeTargetLanguages(IEnumerable<string>? values)
    {
        var normalized = new List<string>();
        if (values is null) return normalized;
        foreach (var item in values)
        {
            var trimmed = (item ?? string.Empty).Trim();
            if (string.IsNullOrWhiteSpace(trimmed)) continue;
            var match = AllowedTargetLanguages.FirstOrDefault(x => string.Equals(x, trimmed, StringComparison.OrdinalIgnoreCase));
            if (match is not null && !normalized.Contains(match, StringComparer.OrdinalIgnoreCase))
            {
                normalized.Add(match);
            }
        }
        return normalized;
    }

    private static string NormalizeAiModeCsv(string? raw, string? task)
    {
        var ordered = new List<string>();
        if (!string.IsNullOrWhiteSpace(raw))
        {
            foreach (var value in raw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                var match = AllowedAiModes.FirstOrDefault(x => string.Equals(x, value, StringComparison.OrdinalIgnoreCase));
                if (match is not null && !ordered.Contains(match, StringComparer.OrdinalIgnoreCase))
                {
                    ordered.Add(match);
                }
            }
        }

        if (string.Equals(task, "translate", StringComparison.OrdinalIgnoreCase) && !ordered.Contains("semantic_translation", StringComparer.OrdinalIgnoreCase))
        {
            ordered.Add("semantic_translation");
        }

        if (ordered.Count == 0)
        {
            ordered.Add(string.Equals(task, "translate", StringComparison.OrdinalIgnoreCase) ? "semantic_translation" : "correction");
        }

        var finalOrdered = new List<string>();
        foreach (var item in new[] { "correction", "semantic_translation", "subtitle_styling" })
        {
            if (ordered.Contains(item, StringComparer.OrdinalIgnoreCase)) finalOrdered.Add(item);
        }
        return string.Join(',', finalOrdered);
    }

    private static string ToClientSourceValue(string? sourceType, string? sourceValue)
    {
        if (string.Equals(sourceType, "file_path", StringComparison.OrdinalIgnoreCase))
        {
            return Path.GetFileName(sourceValue ?? string.Empty);
        }
        return sourceValue ?? string.Empty;
    }

    private static string SerializeStringList(IEnumerable<string> values)
    {
        return JsonSerializer.Serialize(values.Where(x => !string.IsNullOrWhiteSpace(x)).ToList(), JsonOptions);
    }

    private static string? SerializeJsonObject(object? value)
    {
        if (value is null)
            return null;

        try
        {
            return JsonSerializer.Serialize(value, JsonOptions);
        }
        catch
        {
            return null;
        }
    }

    private static object? ParseJsonObject(string? rawJson)
    {
        if (string.IsNullOrWhiteSpace(rawJson))
            return null;

        try
        {
            return JsonSerializer.Deserialize<object>(rawJson, JsonOptions);
        }
        catch
        {
            return null;
        }
    }

    private static Dictionary<string, object?>? ParseJsonDictionary(string? rawJson)
    {
        if (string.IsNullOrWhiteSpace(rawJson))
            return null;

        try
        {
            var parsed = JsonSerializer.Deserialize<Dictionary<string, object?>>(rawJson, JsonOptions);
            return parsed is { Count: > 0 } ? parsed : null;
        }
        catch
        {
            return null;
        }
    }

    private static List<string> ParseStringList(string? rawJson, IEnumerable<string>? fallback = null)
    {
        if (!string.IsNullOrWhiteSpace(rawJson))
        {
            try
            {
                var parsed = JsonSerializer.Deserialize<List<string>>(rawJson, JsonOptions);
                if (parsed is { Count: > 0 })
                {
                    return parsed.Where(x => !string.IsNullOrWhiteSpace(x)).Select(x => x.Trim()).ToList();
                }
            }
            catch
            {
                // ignore and fallback
            }
        }

        return fallback?.Where(x => !string.IsNullOrWhiteSpace(x)).Select(x => x.Trim()).ToList() ?? new List<string>();
    }

    private static List<string> ParseCsv(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return new List<string>();
        return raw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Select(x => x.Trim())
            .ToList();
    }

    private sealed record JobDiagnosticsSnapshot(
        string? StyleSource,
        string? VoiceAnalysisSource,
        string? SceneAnalysisSource,
        string? PreviewModeApplied,
        string? PlannerModelUsed,
        string? ReviewModelUsed,
        string? RequestedAiProvider,
        string? RequestedAiModel,
        string? EffectiveAiProvider,
        string? EffectiveAiModel,
        string? RuntimeTarget,
        bool? ModelInstalledAtSubmission,
        double? SourceDurationSeconds,
        double? OutputDurationSeconds,
        IReadOnlyList<object>? MusicalSegmentDurations,
        IReadOnlyList<object>? Fallbacks,
        IReadOnlyList<object> Diagnostics)
    {
        public static readonly JobDiagnosticsSnapshot Empty = new(null, null, null, null, null, null, null, null, null, null, null, null, null, null, Array.Empty<object>(), Array.Empty<object>(), Array.Empty<object>());
    }

    private static bool ReadCapabilityBool(IDictionary<string, object?>? source, string key, bool fallback = false)
    {
        if (source is null || !source.TryGetValue(key, out var raw) || raw is null)
        {
            return fallback;
        }

        return raw switch
        {
            bool value => value,
            JsonElement { ValueKind: JsonValueKind.True } => true,
            JsonElement { ValueKind: JsonValueKind.False } => false,
            JsonElement { ValueKind: JsonValueKind.String } element when bool.TryParse(element.GetString(), out var parsed) => parsed,
            string text when bool.TryParse(text, out var parsed) => parsed,
            _ => fallback
        };
    }

    private static string? ReadCapabilityString(IDictionary<string, object?>? source, string key)
    {
        if (source is null || !source.TryGetValue(key, out var raw) || raw is null)
        {
            return null;
        }

        return raw switch
        {
            string text => string.IsNullOrWhiteSpace(text) ? null : text.Trim(),
            JsonElement { ValueKind: JsonValueKind.String } element => string.IsNullOrWhiteSpace(element.GetString()) ? null : element.GetString()!.Trim(),
            JsonElement element => element.ToString(),
            _ => raw.ToString()
        };
    }

    private static int? ReadCapabilityInt(IDictionary<string, object?>? source, string key)
    {
        if (source is null || !source.TryGetValue(key, out var raw) || raw is null)
        {
            return null;
        }

        return raw switch
        {
            int value => value,
            long value => checked((int)value),
            JsonElement { ValueKind: JsonValueKind.Number } element when element.TryGetInt32(out var parsed) => parsed,
            JsonElement { ValueKind: JsonValueKind.String } element when int.TryParse(element.GetString(), out var parsed) => parsed,
            string text when int.TryParse(text, out var parsed) => parsed,
            _ => null
        };
    }

    private static IDictionary<string, object?>? ReadCapabilityDictionary(IDictionary<string, object?>? source, string key)
    {
        if (source is null || !source.TryGetValue(key, out var raw) || raw is null)
        {
            return null;
        }

        return raw switch
        {
            IDictionary<string, object?> dict => dict,
            JsonElement { ValueKind: JsonValueKind.Object } element => JsonSerializer.Deserialize<Dictionary<string, object?>>(element.GetRawText(), JsonOptions),
            _ => null
        };
    }

    private static IReadOnlyList<string> ReadCapabilityStringList(IDictionary<string, object?>? source, string key)
    {
        if (source is null || !source.TryGetValue(key, out var raw) || raw is null)
        {
            return Array.Empty<string>();
        }

        if (raw is JsonElement { ValueKind: JsonValueKind.Array } element)
        {
            return element
                .EnumerateArray()
                .Select(x => x.ToString())
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Select(x => x.Trim())
                .ToArray();
        }

        if (raw is IEnumerable<object?> list)
        {
            return list
                .Select(x => x?.ToString())
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Select(x => x!.Trim())
                .ToArray();
        }

        return Array.Empty<string>();
    }

    private static Dictionary<string, IReadOnlyList<string>> ReadCapabilityStringDictionaryOfLists(
        IDictionary<string, object?>? source)
    {
        var result = new Dictionary<string, IReadOnlyList<string>>(StringComparer.OrdinalIgnoreCase);
        if (source is null)
        {
            return result;
        }

        foreach (var entry in source)
        {
            var key = (entry.Key ?? string.Empty).Trim();
            if (string.IsNullOrWhiteSpace(key))
            {
                continue;
            }

            if (entry.Value is JsonElement { ValueKind: JsonValueKind.Array } element)
            {
                result[key] = element
                    .EnumerateArray()
                    .Select(x => x.ToString())
                    .Where(x => !string.IsNullOrWhiteSpace(x))
                    .Select(x => x.Trim())
                    .ToArray();
                continue;
            }

            if (entry.Value is IEnumerable<object?> list)
            {
                result[key] = list
                    .Select(x => x?.ToString())
                    .Where(x => !string.IsNullOrWhiteSpace(x))
                    .Select(x => x!.Trim())
                    .ToArray();
            }
        }

        return result;
    }

    public sealed class SaveTranscriptionPreferencesRequest
    {
        public string? SourceTypeDefault { get; set; }
        public string? Model { get; set; }
        public string? Task { get; set; }
        public string? Language { get; set; }
        public string? OutputFormat { get; set; }
        public List<string>? RequestedOutputs { get; set; }
        public string? DeliveryMode { get; set; }
        public bool GenerateSubtitles { get; set; } = true;
        public bool BurnSubtitlesIntoVideo { get; set; }
        public bool KeepTimestamps { get; set; } = true;
        public bool SplitBySentence { get; set; } = true;
        public bool WordTimestamps { get; set; }
        public bool VadFilter { get; set; } = true;
        public string? DevicePreference { get; set; }
        public string? ComputeType { get; set; }
        public int BeamSize { get; set; } = 5;
        public int? MaxSubtitleChars { get; set; }
        public string? SubtitleStyle { get; set; }
        public string? SubtitleVisualPreset { get; set; }
        public List<string>? TargetLanguages { get; set; }
        public string? VideoDeliveryMode { get; set; }
        public bool AiEnhancementEnabled { get; set; }
        public string? AiProvider { get; set; }
        public string? AiModel { get; set; }
        public string? AiMode { get; set; }
        public string? AiPrompt { get; set; }
        public double? AiTemperature { get; set; }
        public double? AiTopP { get; set; }
        public int? AiMaxTokens { get; set; }
        public int? AiChunkChars { get; set; }
        public bool AiUseVisualContext { get; set; }
        public int? AiFrameSampleSeconds { get; set; }
        public bool PreserveTimestamps { get; set; } = true;
        public int AiRevisionPasses { get; set; } = 3;
        public string? UseAdvancedAlignment { get; set; }
        public bool EnableOnlineContext { get; set; }
        public object? ContextHints { get; set; }
        public string? QualityProfile { get; set; }
        public string? ContentMode { get; set; }
        public string? SpeakerStyleMode { get; set; }
        public string? StyleIntensity { get; set; }
        public string? RenderedPreviewMode { get; set; }
        public string? AnimeSongLayoutMode { get; set; }
        public string? KaraokeGranularity { get; set; }
    }

    public sealed class CreateTranscriptionJobRequest
    {
        public string? SourceType { get; set; }
        public string? SourceValue { get; set; }
        public string? Model { get; set; }
        public string? Task { get; set; }
        public string? Language { get; set; }
        public string? OutputFormat { get; set; }
        public List<string>? RequestedOutputs { get; set; }
        public string? DeliveryMode { get; set; }
        public bool GenerateSubtitles { get; set; } = true;
        public bool BurnSubtitlesIntoVideo { get; set; }
        public bool KeepTimestamps { get; set; } = true;
        public bool SplitBySentence { get; set; } = true;
        public bool WordTimestamps { get; set; }
        public bool VadFilter { get; set; } = true;
        public string? DevicePreference { get; set; }
        public string? ComputeType { get; set; }
        public int BeamSize { get; set; } = 5;
        public int? MaxSubtitleChars { get; set; }
        public string? SubtitleStyle { get; set; }
        public string? SubtitleVisualPreset { get; set; }
        public List<string>? TargetLanguages { get; set; }
        public string? VideoDeliveryMode { get; set; }
        public bool AiEnhancementEnabled { get; set; }
        public string? AiProvider { get; set; }
        public string? AiModel { get; set; }
        public string? AiMode { get; set; }
        public string? AiPrompt { get; set; }
        public double? AiTemperature { get; set; }
        public double? AiTopP { get; set; }
        public int? AiMaxTokens { get; set; }
        public int? AiChunkChars { get; set; }
        public bool AiUseVisualContext { get; set; }
        public int? AiFrameSampleSeconds { get; set; }
        public bool PreserveTimestamps { get; set; } = true;
        public int AiRevisionPasses { get; set; } = 3;
        public string? UseAdvancedAlignment { get; set; }
        public bool EnableOnlineContext { get; set; }
        public object? ContextHints { get; set; }
        public string? QualityProfile { get; set; }
        public string? ContentMode { get; set; }
        public string? SpeakerStyleMode { get; set; }
        public string? StyleIntensity { get; set; }
        public string? RenderedPreviewMode { get; set; }
        public string? AnimeSongLayoutMode { get; set; }
        public string? KaraokeGranularity { get; set; }
    }

    public sealed class CreateTranscriptionUploadRequest
    {
        public IFormFile? File { get; set; }

        public string? Model { get; set; }
        public string? Task { get; set; }
        public string? Language { get; set; }
        public string? OutputFormat { get; set; }
        public string? RequestedOutputsCsv { get; set; }
        public string? RequestedOutputsJson { get; set; }
        public string? DeliveryMode { get; set; }
        public bool GenerateSubtitles { get; set; } = true;
        public bool BurnSubtitlesIntoVideo { get; set; }
        public bool KeepTimestamps { get; set; } = true;
        public bool SplitBySentence { get; set; } = true;
        public bool WordTimestamps { get; set; }
        public bool VadFilter { get; set; } = true;
        public string? DevicePreference { get; set; }
        public string? ComputeType { get; set; }
        public int BeamSize { get; set; } = 5;
        public int? MaxSubtitleChars { get; set; }
        public string? SubtitleStyle { get; set; }
        public string? SubtitleVisualPreset { get; set; }
        public string? TargetLanguagesCsv { get; set; }
        public string? TargetLanguagesJson { get; set; }
        public string? VideoDeliveryMode { get; set; }
        public bool AiEnhancementEnabled { get; set; }
        public string? AiProvider { get; set; }
        public string? AiModel { get; set; }
        public string? AiMode { get; set; }
        public string? AiPrompt { get; set; }
        public double? AiTemperature { get; set; }
        public double? AiTopP { get; set; }
        public int? AiMaxTokens { get; set; }
        public int? AiChunkChars { get; set; }
        public bool AiUseVisualContext { get; set; }
        public int? AiFrameSampleSeconds { get; set; }
        public bool PreserveTimestamps { get; set; } = true;
        public int AiRevisionPasses { get; set; } = 3;
        public string? UseAdvancedAlignment { get; set; }
        public bool EnableOnlineContext { get; set; }
        public string? ContextHintsJson { get; set; }
        public string? QualityProfile { get; set; }
        public string? ContentMode { get; set; }
        public string? SpeakerStyleMode { get; set; }
        public string? StyleIntensity { get; set; }
        public string? RenderedPreviewMode { get; set; }
        public string? AnimeSongLayoutMode { get; set; }
        public string? KaraokeGranularity { get; set; }
    }

    public sealed class ModelDownloadRequest
    {
        public string? Provider { get; set; }
        public string? Model { get; set; }
    }
}
