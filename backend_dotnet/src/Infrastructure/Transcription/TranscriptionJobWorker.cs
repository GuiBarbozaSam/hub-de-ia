using System.Text.Json;
using Domain.Entities;
using Infrastructure.Persistence;
using Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Infrastructure.Transcription;

public sealed class TranscriptionJobWorker : BackgroundService
{
    private static readonly TimeSpan IdleDelay = TimeSpan.FromSeconds(2);

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly PythonTranscriptionSettings _settings;
    private readonly ILogger<TranscriptionJobWorker> _logger;

    public TranscriptionJobWorker(
        IServiceScopeFactory scopeFactory,
        PythonTranscriptionSettings settings,
        ILogger<TranscriptionJobWorker> logger)
    {
        _scopeFactory = scopeFactory;
        _settings = settings;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var claimed = await TryClaimNextJobAsync(stoppingToken);
                if (claimed is null)
                {
                    await Task.Delay(IdleDelay, stoppingToken);
                    continue;
                }

                PythonTranscriptionResult result;
                try
                {
                    using var runScope = _scopeFactory.CreateScope();
                    var client = runScope.ServiceProvider.GetRequiredService<PythonTranscriptionClient>();

                    result = await client.RunAsync(new PythonTranscriptionRequest
                    {
                        SourceType = claimed.SourceType,
                        SourceValue = claimed.SourceValue,
                        Model = claimed.Model,
                        Task = claimed.Task,
                        Language = claimed.Language,
                        OutputFormat = claimed.OutputFormat,
                        RequestedOutputs = claimed.RequestedOutputs,
                        RequestedOutputsCsv = string.Join(",", claimed.RequestedOutputs),
                        DeliveryMode = claimed.DeliveryMode,
                        GenerateSubtitles = claimed.GenerateSubtitles,
                        BurnSubtitlesIntoVideo = claimed.BurnSubtitlesIntoVideo,
                        KeepTimestamps = claimed.KeepTimestamps,
                        SplitBySentence = claimed.SplitBySentence,
                        WordTimestamps = claimed.WordTimestamps,
                        VadFilter = claimed.VadFilter,
                        DevicePreference = claimed.DevicePreference,
                        ComputeType = claimed.ComputeType,
                        BeamSize = claimed.BeamSize,
                        MaxSubtitleChars = claimed.MaxSubtitleChars,
                        SubtitleStyle = claimed.SubtitleStyle,
                        SubtitleVisualPreset = claimed.SubtitleStyle,
                        TargetLanguages = claimed.TargetLanguages,
                        VideoDeliveryMode = claimed.VideoDeliveryMode,
                        AiEnhancementEnabled = claimed.AiEnhancementEnabled,
                        AiProvider = claimed.AiProvider,
                        AiModel = claimed.AiModel,
                        AiMode = claimed.AiMode,
                        AiPrompt = claimed.AiPrompt,
                        AiTemperature = claimed.AiTemperature,
                        AiTopP = claimed.AiTopP,
                        AiMaxTokens = claimed.AiMaxTokens,
                        AiChunkChars = claimed.AiChunkChars,
                        AiUseVisualContext = claimed.AiUseVisualContext,
                        AiFrameSampleSeconds = claimed.AiFrameSampleSeconds,
                        PreserveTimestamps = claimed.PreserveTimestamps,
                        AiRevisionPasses = claimed.AiRevisionPasses,
                        UseAdvancedAlignment = claimed.UseAdvancedAlignment,
                        EnableOnlineContext = claimed.EnableOnlineContext,
                        ContextHints = DeserializeJsonElement(claimed.ContextHintsJson),
                        QualityProfile = claimed.QualityProfile,
                        ContentMode = claimed.ContentMode,
                        SpeakerStyleMode = claimed.SpeakerStyleMode,
                        StyleIntensity = claimed.StyleIntensity,
                        RenderedPreviewMode = claimed.RenderedPreviewMode,
                        AnimeSongLayoutMode = claimed.AnimeSongLayoutMode,
                        KaraokeGranularity = claimed.KaraokeGranularity,
                        JobId = claimed.Id.ToString(),
                        ProgressCallbackUrl = BuildProgressCallbackUrl(claimed.Id),
                        ProgressCallbackToken = _settings.InternalApiKey
                    }, stoppingToken);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Erro ao processar job {JobId}.", claimed.Id);
                    await MarkJobAsErrorAsync(
                        claimed.Id,
                        $"Falha ao executar job de transcrição: {ex.Message}",
                        stoppingToken);
                    continue;
                }

                await FinalizeJobAsync(claimed, result, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Falha inesperada no loop do TranscriptionJobWorker.");
                await Task.Delay(IdleDelay, stoppingToken);
            }
        }
    }

    private async Task<ClaimedJobSnapshot?> TryClaimNextJobAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var candidate = await db.TranscriptionJobs
            .AsNoTracking()
            .Where(x => x.Status == "pending")
            .OrderBy(x => x.CreatedAtUtc)
            .Select(x => new { x.Id })
            .FirstOrDefaultAsync(ct);

        if (candidate is null)
            return null;

        var affected = await db.TranscriptionJobs
            .Where(x => x.Id == candidate.Id && x.Status == "pending")
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(x => x.Status, "processing")
                .SetProperty(x => x.ProgressPercent, 5)
                .SetProperty(x => x.CurrentStage, "ingestion")
                .SetProperty(x => x.CurrentPass, 0)
                .SetProperty(x => x.StartedAtUtc, DateTime.UtcNow)
                .SetProperty(x => x.FinishedAtUtc, (DateTime?)null)
                .SetProperty(x => x.ErrorMessage, (string?)null), ct);

        if (affected == 0)
            return null;

        return await db.TranscriptionJobs
            .AsNoTracking()
            .Where(x => x.Id == candidate.Id)
            .Select(x => new ClaimedJobSnapshot
            {
                Id = x.Id,
                UserId = x.UserId,
                SourceType = x.SourceType,
                SourceValue = x.SourceValue,
                Model = x.Model,
                Task = x.Task,
                Language = x.Language,
                OutputFormat = x.OutputFormat,
                RequestedOutputsJson = x.RequestedOutputsJson,
                DeliveryMode = x.DeliveryMode,
                TargetLanguagesJson = x.TargetLanguagesJson,
                VideoDeliveryMode = x.VideoDeliveryMode,
                GenerateSubtitles = x.GenerateSubtitles,
                BurnSubtitlesIntoVideo = x.BurnSubtitlesIntoVideo,
                KeepTimestamps = x.KeepTimestamps,
                SplitBySentence = x.SplitBySentence,
                WordTimestamps = x.WordTimestamps,
                VadFilter = x.VadFilter,
                DevicePreference = x.DevicePreference,
                ComputeType = x.ComputeType,
                BeamSize = x.BeamSize,
                MaxSubtitleChars = x.MaxSubtitleChars,
                SubtitleStyle = x.SubtitleStyle,
                AiEnhancementEnabled = x.AiEnhancementEnabled,
                AiProvider = x.AiProvider,
                AiModel = x.AiModel,
                AiMode = x.AiMode,
                AiPrompt = x.AiPrompt,
                AiTemperature = x.AiTemperature,
                AiTopP = x.AiTopP,
                AiMaxTokens = x.AiMaxTokens,
                AiChunkChars = x.AiChunkChars,
                AiUseVisualContext = x.AiUseVisualContext,
                AiFrameSampleSeconds = x.AiFrameSampleSeconds,
                PreserveTimestamps = x.PreserveTimestamps,
                AiRevisionPasses = x.AiRevisionPasses,
                UseAdvancedAlignment = x.UseAdvancedAlignment,
                EnableOnlineContext = x.EnableOnlineContext,
                ContextHintsJson = x.ContextHintsJson,
                QualityProfile = x.QualityProfile,
                ContentMode = x.ContentMode,
                SpeakerStyleMode = x.SpeakerStyleMode,
                StyleIntensity = x.StyleIntensity,
                RenderedPreviewMode = x.RenderedPreviewMode,
                AnimeSongLayoutMode = x.AnimeSongLayoutMode,
                KaraokeGranularity = x.KaraokeGranularity
            })
            .FirstOrDefaultAsync(ct);
    }

    private async Task FinalizeJobAsync(
        ClaimedJobSnapshot claimed,
        PythonTranscriptionResult result,
        CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var storage = scope.ServiceProvider.GetRequiredService<ILocalMediaStorage>();

        var job = await db.TranscriptionJobs
            .Include(x => x.Outputs)
            .FirstOrDefaultAsync(x => x.Id == claimed.Id, ct);

        if (job is null)
            return;

        if (job.Outputs.Count > 0)
        {
            db.TranscriptionJobOutputs.RemoveRange(job.Outputs);
            job.Outputs.Clear();
        }

        var requestedOutputs = ResolveRequestedOutputs(job);

        var textCount = 0;
        var fileCount = 0;
        var translationCount = 0;
        var enhancedCount = 0;
        var hasAss = false;
        var hasVideoBurned = false;
        var hasVideoMuxed = false;

        if (requestedOutputs.Contains("txt", StringComparer.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(result.Text))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "text",
                ContentText = result.Text
            });
            textCount++;
        }

        if (requestedOutputs.Contains("srt", StringComparer.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(result.Srt))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "srt",
                ContentText = result.Srt
            });
            textCount++;
        }

        if (requestedOutputs.Contains("vtt", StringComparer.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(result.Vtt))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "vtt",
                ContentText = result.Vtt
            });
            textCount++;
        }

        if (requestedOutputs.Contains("ass", StringComparer.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(result.AssPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "ass",
                FilePath = storage.NormalizeStoredPath(result.AssPath)
            });

            hasAss = true;
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.VideoOutputPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "video_burned",
                FilePath = storage.NormalizeStoredPath(result.VideoOutputPath)
            });

            hasVideoBurned = true;
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.VideoMuxedPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "video_muxed",
                FilePath = storage.NormalizeStoredPath(result.VideoMuxedPath)
            });

            hasVideoMuxed = true;
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.RenderPreviewPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "render_preview",
                FilePath = storage.NormalizeStoredPath(result.RenderPreviewPath)
            });
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.KaraokePlanPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "karaoke_plan",
                FilePath = storage.NormalizeStoredPath(result.KaraokePlanPath)
            });
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.SceneMapPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "scene_map",
                FilePath = storage.NormalizeStoredPath(result.SceneMapPath)
            });
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.SpeakerMapPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "speaker_map",
                FilePath = storage.NormalizeStoredPath(result.SpeakerMapPath)
            });
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.LyricAlignmentPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "lyric_alignment",
                FilePath = storage.NormalizeStoredPath(result.LyricAlignmentPath)
            });
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.TranslationManifestPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "translations_manifest",
                FilePath = storage.NormalizeStoredPath(result.TranslationManifestPath)
            });
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.DiagnosticsPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "job_diagnostics",
                FilePath = storage.NormalizeStoredPath(result.DiagnosticsPath)
            });
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.QualityReportPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "quality_report",
                FilePath = storage.NormalizeStoredPath(result.QualityReportPath)
            });
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.StyleMapPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "style_map",
                FilePath = storage.NormalizeStoredPath(result.StyleMapPath)
            });
            fileCount++;
        }

        if (!string.IsNullOrWhiteSpace(result.AlignmentReportPath))
        {
            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = job.Id,
                OutputType = "alignment_report",
                FilePath = storage.NormalizeStoredPath(result.AlignmentReportPath)
            });
            fileCount++;
        }

        translationCount += AddManifestOutputs(db, storage, job.Id, result.TranslationManifestPath);
        enhancedCount += AddEnhancedOutputs(db, storage, job.Id, result.EnhancedDirPath);

        var missingArtifacts = EvaluateMissingArtifacts(
            claimed: claimed,
            result: result,
            requestedOutputs: requestedOutputs,
            textCount: textCount,
            hasAss: hasAss,
            hasVideoBurned: hasVideoBurned,
            hasVideoMuxed: hasVideoMuxed,
            translationCount: translationCount,
            enhancedCount: enhancedCount);

        var hasHardError = string.Equals(result.Status, "error", StringComparison.OrdinalIgnoreCase)
            || !string.IsNullOrWhiteSpace(result.Error);

        job.ProgressPercent = 100;
        job.Status = (!hasHardError && missingArtifacts.Count == 0) ? "completed" : "error";
        job.CurrentStage = string.IsNullOrWhiteSpace(result.CurrentStage)
            ? (job.Status == "completed" ? "completed" : "error")
            : result.CurrentStage.Trim();
        job.CurrentPass = result.CurrentPass ?? job.CurrentPass;
        job.TotalPasses = Math.Max(job.TotalPasses, result.TotalPasses ?? job.TotalPasses);
        job.LanguageDetected = result.LanguageDetected;
        job.DurationSeconds = result.DurationSeconds;
        job.ErrorMessage = BuildJobMessage(result, missingArtifacts);
        job.StyleSource = result.StyleSource ?? job.StyleSource;
        job.QualitySummaryJson = SerializeJsonObject(result.QualitySummary);
        job.TranslationStatusesJson = SerializeJsonObject(result.TranslationStatuses);
        job.CapabilityProfileJson = SerializeJsonObject(result.CapabilityProfile);
        job.DetectedContentType = result.DetectedContentType ?? job.DetectedContentType;
        job.ContentDetectionConfidence = result.ContentDetectionConfidence ?? job.ContentDetectionConfidence;
        job.SpeakerModeApplied = result.SpeakerModeApplied ?? job.SpeakerModeApplied;
        job.KaraokeModeApplied = result.KaraokeModeApplied ?? job.KaraokeModeApplied;
        job.FinishedAtUtc = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);
    }

    private static List<string> EvaluateMissingArtifacts(
        ClaimedJobSnapshot claimed,
        PythonTranscriptionResult result,
        List<string> requestedOutputs,
        int textCount,
        bool hasAss,
        bool hasVideoBurned,
        bool hasVideoMuxed,
        int translationCount,
        int enhancedCount)
    {
        var missing = new List<string>();
        var instrumentalOnly = IsInstrumentalOnlyResult(result);

        var expectedTextCount = requestedOutputs.Count(x =>
            x.Equals("txt", StringComparison.OrdinalIgnoreCase) ||
            x.Equals("srt", StringComparison.OrdinalIgnoreCase) ||
            x.Equals("vtt", StringComparison.OrdinalIgnoreCase));

        if (expectedTextCount > 0 && textCount < expectedTextCount && !instrumentalOnly)
            missing.Add("saídas textuais principais");

        if (requestedOutputs.Contains("ass", StringComparer.OrdinalIgnoreCase) && !hasAss)
            missing.Add("arquivo ASS principal");

        if (requestedOutputs.Contains("video_burned", StringComparer.OrdinalIgnoreCase) && !hasVideoBurned)
            missing.Add("vídeo com legenda queimada");

        var requestedTranslations = claimed.TargetLanguages.Count;
        if (requestedTranslations > 0 && translationCount == 0)
            missing.Add("arquivos de tradução");

        if (string.Equals(claimed.VideoDeliveryMode, "mux_subtitles", StringComparison.OrdinalIgnoreCase) &&
            requestedTranslations > 0 &&
            !hasVideoMuxed)
        {
            missing.Add("vídeo com múltiplas legendas");
        }

        if (claimed.AiEnhancementEnabled && enhancedCount == 0)
            missing.Add("arquivos aprimorados por IA");

        return missing;
    }

    private static bool IsInstrumentalOnlyResult(PythonTranscriptionResult result)
    {
        if (result.TranslationStatuses is null || result.TranslationStatuses.Count == 0)
            return false;

        var published = 0;
        foreach (var raw in result.TranslationStatuses.Values)
        {
            var item = AsDictionary(raw);
            if (item is null)
                continue;

            var status = ReadJsonString(item, "status");
            if (!string.Equals(status, "published", StringComparison.OrdinalIgnoreCase))
                continue;

            published++;
            var source = ReadJsonString(item, "source");
            if (!string.Equals(source, "instrumental_passthrough", StringComparison.OrdinalIgnoreCase))
                return false;
        }

        return published > 0;
    }

    private static Dictionary<string, object?>? AsDictionary(object? raw)
    {
        return raw switch
        {
            Dictionary<string, object?> dict => dict,
            JsonElement { ValueKind: JsonValueKind.Object } element => JsonSerializer.Deserialize<Dictionary<string, object?>>(element.GetRawText(), JsonOptions),
            _ => null
        };
    }

    private static string? ReadJsonString(Dictionary<string, object?> source, string key)
    {
        if (!source.TryGetValue(key, out var raw) || raw is null)
            return null;

        return raw switch
        {
            string text => string.IsNullOrWhiteSpace(text) ? null : text.Trim(),
            JsonElement { ValueKind: JsonValueKind.String } element => string.IsNullOrWhiteSpace(element.GetString()) ? null : element.GetString()!.Trim(),
            JsonElement element => element.ToString(),
            _ => raw.ToString()
        };
    }

    private static string? BuildJobMessage(PythonTranscriptionResult result, List<string> missingArtifacts)
    {
        var parts = new List<string>();

        if (!string.IsNullOrWhiteSpace(result.Error))
            parts.Add(result.Error.Trim());

        if (missingArtifacts.Count > 0)
            parts.Add($"O processamento terminou sem gerar todos os artefatos solicitados: {string.Join(", ", missingArtifacts)}.");

        if (result.Warnings is { Count: > 0 })
        {
            var warnings = result.Warnings
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Select(x => x.Trim())
                .ToList();

            if (warnings.Count > 0)
                parts.Add(string.Join(" | ", warnings));
        }

        var joined = string.Join(" | ", parts.Where(x => !string.IsNullOrWhiteSpace(x)));
        return string.IsNullOrWhiteSpace(joined) ? null : joined;
    }

    private static int AddManifestOutputs(
        AppDbContext db,
        ILocalMediaStorage storage,
        Guid jobId,
        string? manifestPath)
    {
        if (string.IsNullOrWhiteSpace(manifestPath))
            return 0;

        var absolutePath = storage.ResolveManagedFilePath(storage.NormalizeStoredPath(manifestPath));
        if (!File.Exists(absolutePath))
            return 0;

        JsonDocument document;
        try
        {
            var json = File.ReadAllText(absolutePath);
            document = JsonDocument.Parse(json);
        }
        catch
        {
            return 0;
        }

        using (document)
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object)
                return 0;

            var added = 0;

            JsonElement languagesElement;
            if (document.RootElement.TryGetProperty("languages", out var structuredLanguages) &&
                structuredLanguages.ValueKind == JsonValueKind.Object)
            {
                languagesElement = structuredLanguages;
            }
            else
            {
                languagesElement = document.RootElement;
            }

            foreach (var languageEntry in languagesElement.EnumerateObject())
            {
                var languageCode = SanitizeTag(languageEntry.Name);
                var languageValue = languageEntry.Value;
                JsonElement outputsElement;

                if (languageValue.ValueKind == JsonValueKind.Object &&
                    languageValue.TryGetProperty("status", out var statusElement) &&
                    !string.Equals(statusElement.GetString(), "published", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                if (languageValue.ValueKind == JsonValueKind.Object &&
                    languageValue.TryGetProperty("outputs", out var nestedOutputs) &&
                    nestedOutputs.ValueKind == JsonValueKind.Object)
                {
                    outputsElement = nestedOutputs;
                }
                else if (languageValue.ValueKind == JsonValueKind.Object)
                {
                    outputsElement = languageValue;
                }
                else
                {
                    continue;
                }

                foreach (var fileEntry in outputsElement.EnumerateObject())
                {
                    if (fileEntry.Value.ValueKind != JsonValueKind.String)
                        continue;

                    var rawPath = fileEntry.Value.GetString();
                    if (string.IsNullOrWhiteSpace(rawPath))
                        continue;

                    var path = storage.NormalizeStoredPath(rawPath);
                    var kind = SanitizeTag(fileEntry.Name);

                    db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
                    {
                        JobId = jobId,
                        OutputType = $"translation_{kind}_{languageCode}",
                        FilePath = path
                    });

                    added++;
                }
            }

            return added;
        }
    }

    private static int AddEnhancedOutputs(
        AppDbContext db,
        ILocalMediaStorage storage,
        Guid jobId,
        string? enhancedDirPath)
    {
        if (string.IsNullOrWhiteSpace(enhancedDirPath))
            return 0;

        var absoluteDir = storage.ResolveManagedFilePath(storage.NormalizeStoredPath(enhancedDirPath));
        if (!Directory.Exists(absoluteDir))
            return 0;

        var added = 0;

        foreach (var file in Directory.EnumerateFiles(absoluteDir))
        {
            var ext = Path.GetExtension(file).TrimStart('.').ToLowerInvariant();
            if (ext is not ("txt" or "srt" or "vtt" or "ass"))
                continue;

            db.TranscriptionJobOutputs.Add(new TranscriptionJobOutput
            {
                JobId = jobId,
                OutputType = $"enhanced_{ext}",
                FilePath = storage.NormalizeStoredPath(file)
            });

            added++;
        }

        return added;
    }

    private static string SanitizeTag(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return "unknown";

        return new string(value.Where(ch => char.IsLetterOrDigit(ch) || ch is '-' or '_').ToArray());
    }

    private static List<string> ResolveRequestedOutputs(TranscriptionJob job)
    {
        var fromJson = job.GetRequestedOutputs();
        if (fromJson.Count > 0)
            return NormalizeRequestedOutputs(fromJson);

        return NormalizeRequestedOutputs(BuildRequestedOutputs(job.OutputFormat, job.BurnSubtitlesIntoVideo, job.AiEnhancementEnabled, job.AiMode));
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

    private static bool ContainsAiMode(string? raw, string expected)
    {
        return (raw ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Contains(expected, StringComparer.OrdinalIgnoreCase);
    }

    private static List<string> NormalizeRequestedOutputs(IEnumerable<string> values)
    {
        var ordered = new List<string>();

        if (values.Contains("txt", StringComparer.OrdinalIgnoreCase))
            ordered.Add("txt");

        if (values.Contains("srt", StringComparer.OrdinalIgnoreCase))
            ordered.Add("srt");

        if (values.Contains("vtt", StringComparer.OrdinalIgnoreCase))
            ordered.Add("vtt");

        if (values.Contains("ass", StringComparer.OrdinalIgnoreCase))
            ordered.Add("ass");

        if (values.Contains("video_burned", StringComparer.OrdinalIgnoreCase))
            ordered.Add("video_burned");

        return ordered.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    private async Task MarkJobAsErrorAsync(Guid jobId, string errorMessage, CancellationToken ct)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

            await db.TranscriptionJobs
                .Where(x => x.Id == jobId)
                .ExecuteUpdateAsync(setters => setters
                    .SetProperty(x => x.Status, "error")
                    .SetProperty(x => x.ProgressPercent, 100)
                    .SetProperty(x => x.CurrentStage, "error")
                    .SetProperty(x => x.ErrorMessage, errorMessage)
                    .SetProperty(x => x.FinishedAtUtc, DateTime.UtcNow), ct);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erro adicional ao salvar falha do job {JobId}.", jobId);
        }
    }

    private sealed class ClaimedJobSnapshot
    {
        public Guid Id { get; set; }
        public string UserId { get; set; } = "";
        public string SourceType { get; set; } = "";
        public string SourceValue { get; set; } = "";
        public string Model { get; set; } = "";
        public string Task { get; set; } = "";
        public string Language { get; set; } = "";
        public string OutputFormat { get; set; } = "";
        public string RequestedOutputsJson { get; set; } = "[]";
        public string DeliveryMode { get; set; } = "standard";
        public string TargetLanguagesJson { get; set; } = "[]";
        public string VideoDeliveryMode { get; set; } = "standard";
        public bool GenerateSubtitles { get; set; }
        public bool BurnSubtitlesIntoVideo { get; set; }
        public bool KeepTimestamps { get; set; }
        public bool SplitBySentence { get; set; }
        public bool WordTimestamps { get; set; }
        public bool VadFilter { get; set; }
        public string DevicePreference { get; set; } = "";
        public string ComputeType { get; set; } = "";
        public int BeamSize { get; set; }
        public int? MaxSubtitleChars { get; set; }
        public string SubtitleStyle { get; set; } = "";
        public bool AiEnhancementEnabled { get; set; }
        public string AiProvider { get; set; } = "ollama_project";
        public string AiModel { get; set; } = "";
        public string AiMode { get; set; } = "";
        public string? AiPrompt { get; set; }
        public double? AiTemperature { get; set; }
        public double? AiTopP { get; set; }
        public int? AiMaxTokens { get; set; }
        public int? AiChunkChars { get; set; }
        public bool AiUseVisualContext { get; set; }
        public int? AiFrameSampleSeconds { get; set; }
        public bool PreserveTimestamps { get; set; }
        public int AiRevisionPasses { get; set; }
        public string UseAdvancedAlignment { get; set; } = "auto";
        public bool EnableOnlineContext { get; set; }
        public string? ContextHintsJson { get; set; }
        public string QualityProfile { get; set; } = "balanced";
        public string ContentMode { get; set; } = "episode";
        public string SpeakerStyleMode { get; set; } = "heuristic";
        public string StyleIntensity { get; set; } = "thematic";
        public string RenderedPreviewMode { get; set; } = "fast";
        public string AnimeSongLayoutMode { get; set; } = "off";
        public string KaraokeGranularity { get; set; } = "off";

        public List<string> RequestedOutputs
        {
            get
            {
                try
                {
                    var parsed = JsonSerializer.Deserialize<List<string>>(RequestedOutputsJson, JsonOptions);
                    return parsed?
                        .Where(x => !string.IsNullOrWhiteSpace(x))
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .ToList() ?? [];
                }
                catch
                {
                    return [];
                }
            }
        }

        public List<string> TargetLanguages
        {
            get
            {
                try
                {
                    var parsed = JsonSerializer.Deserialize<List<string>>(TargetLanguagesJson, JsonOptions);
                    return parsed?
                        .Where(x => !string.IsNullOrWhiteSpace(x))
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .ToList() ?? [];
                }
                catch
                {
                    return [];
                }
            }
        }
    }

    private string BuildProgressCallbackUrl(Guid jobId)
    {
        var baseUrl = (_settings.CallbackBaseUrl ?? string.Empty).Trim().TrimEnd('/');
        if (string.IsNullOrWhiteSpace(baseUrl))
            return $"/internal/transcription/jobs/{jobId}/progress";

        return $"{baseUrl}/internal/transcription/jobs/{jobId}/progress";
    }

    private static JsonElement? DeserializeJsonElement(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return null;

        try
        {
            return JsonSerializer.Deserialize<JsonElement>(raw, JsonOptions);
        }
        catch
        {
            return null;
        }
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
}
