using System.Net;
using System.Net.Http;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Domain.Entities;
using Infrastructure.Persistence;
using Infrastructure.Storage;
using Infrastructure.Transcription;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.Routing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.AspNetCore.Routing;
using WebApi.Controllers;
using Xunit;

namespace WebApi.Tests;

public sealed class TranscriptionControllerTests
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task GetCapabilities_ReturnsEffectiveTimeoutMetadata()
    {
        var responseJson = """
        {
          "service": "transcription",
          "faster_whisper_installed": true,
          "default_model": "large-v3",
          "device_mode": "auto",
          "compute_type_mode": "float16",
          "hardware": {
            "device": "cuda",
            "voiceAnalysisAvailable": true,
            "sceneAnalysisAvailable": true,
            "diarizationAvailable": false,
            "advancedAlignmentAvailable": true,
            "maxSupportedKaraokeGranularity": "syllable"
          },
          "ollama": {
            "installedModels": ["gemma3:4b", "qwen2.5:14b"]
          },
          "profiles": {
            "balanced": {
              "structuredTimeoutSeconds": 90,
              "styleTimeoutSeconds": 180
            }
          },
          "recommendedProfile": "balanced",
          "structuredTimeoutSeconds": 90,
          "styleTimeoutSeconds": 180,
          "timeoutProfileApplied": "balanced"
        }
        """;

        var settings = new PythonTranscriptionSettings
        {
            BaseUrl = "http://127.0.0.1:8001",
            InternalApiKey = "local_test_key",
            TimeoutMinutes = 480
        };
        var client = CreatePythonClient(responseJson, settings);
        var controller = new TranscriptionController(
            db: null!,
            storage: new FakeStorage(),
            pythonClient: client,
            pythonSettings: settings);

        var action = await controller.GetCapabilities(CancellationToken.None);
        var ok = Assert.IsType<OkObjectResult>(action);
        var payload = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(
            JsonSerializer.Serialize(ok.Value, JsonOptions),
            JsonOptions)!;

        Assert.Equal(480, payload["jobTimeoutMinutes"].GetInt32());
        Assert.Equal(90, payload["structuredTimeoutSeconds"].GetInt32());
        Assert.Equal(180, payload["styleTimeoutSeconds"].GetInt32());
        Assert.Equal("balanced", payload["timeoutProfileApplied"].GetString());
    }

    [Fact]
    public async Task GetOptions_UsesOnlySelectableMultimodalModelsForDefaultProvider()
    {
        var responseJson = """
        {
          "service": "transcription",
          "providers": [
            {
              "id": "ollama_project",
              "label": "Ollama do projeto",
              "type": "ollama",
              "available": true,
              "installedModels": ["qwen2.5vl:7b", "qwen2.5:14b", "gemma3:4b"],
              "downloadableModels": ["qwen2.5vl:32b", "qwen3-vl:30b-a3b-instruct-q4_K_M"],
              "multimodalModels": ["qwen2.5vl:7b", "qwen2.5vl:32b", "qwen3-vl:30b-a3b-instruct-q4_K_M"],
              "defaultModel": "qwen2.5vl:7b"
            },
            {
              "id": "remote_api",
              "label": "API remota",
              "type": "remote_api",
              "available": true,
              "installedModels": ["qwen3-vl:30b-a3b-instruct-q4_K_M"],
              "downloadableModels": [],
              "multimodalModels": ["qwen3-vl:30b-a3b-instruct-q4_K_M"],
              "defaultModel": "qwen3-vl:30b-a3b-instruct-q4_K_M"
            }
          ],
          "installedModelsByProvider": {
            "ollama_project": ["qwen2.5vl:7b", "qwen2.5:14b", "gemma3:4b"],
            "remote_api": ["qwen3-vl:30b-a3b-instruct-q4_K_M"]
          },
          "downloadableModelsByProvider": {
            "ollama_project": ["qwen2.5vl:32b", "qwen3-vl:30b-a3b-instruct-q4_K_M"],
            "remote_api": []
          }
        }
        """;

        var settings = new PythonTranscriptionSettings
        {
            BaseUrl = "http://127.0.0.1:8001",
            InternalApiKey = "local_test_key",
            TimeoutMinutes = 480
        };
        var client = CreatePythonClient(responseJson, settings);
        var controller = new TranscriptionController(
            db: null!,
            storage: new FakeStorage(),
            pythonClient: client,
            pythonSettings: settings);

        var action = await controller.GetOptions(CancellationToken.None);
        var ok = Assert.IsType<OkObjectResult>(action);
        var payload = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(
            JsonSerializer.Serialize(ok.Value, JsonOptions),
            JsonOptions)!;

        var aiModels = payload["aiModels"].EnumerateArray().Select(x => x.GetString()).ToArray();
        Assert.Contains("qwen2.5vl:7b", aiModels);
        Assert.DoesNotContain("qwen2.5:14b", aiModels);
        Assert.DoesNotContain("gemma3:4b", aiModels);
    }

    [Fact]
    public async Task GetJob_ReturnsTimeoutProfileAndGateMetadata()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString("N"))
            .Options;

        await using var db = new AppDbContext(options);

        var job = new TranscriptionJob
        {
            Id = Guid.NewGuid(),
            UserId = "user-1",
            SourceType = "file_path",
            SourceValue = "uploads/source.mkv",
            Model = "large-v3",
            Task = "translate",
            Language = "auto",
            OutputFormat = "all",
            RequestedOutputsJson = """["txt","srt","vtt","ass"]""",
            DeliveryMode = "standard",
            TargetLanguagesJson = """["en"]""",
            VideoDeliveryMode = "mux_subtitles",
            AiEnhancementEnabled = true,
            AiProvider = "ollama",
            AiModel = "qwen2.5:14b",
            AiMode = "correction,semantic_translation,subtitle_styling",
            QualityProfile = "balanced",
            ContentMode = "anime_song",
            RenderedPreviewMode = "rendered",
            SpeakerStyleMode = "advanced",
            KaraokeGranularity = "syllable",
            Status = "completed",
            ProgressPercent = 100,
            StyleSource = "ai_plan",
            CapabilityProfileJson = """
            {
              "timeoutProfileApplied": "balanced",
              "structuredTimeoutSeconds": 90,
              "styleTimeoutSeconds": 180
            }
            """,
            QualitySummaryJson = """
            {
              "releaseGate": {
                "ready": true,
                "reasons": [],
                "criticalFallbacks": []
              }
            }
            """,
            TranslationStatusesJson = """
            {
              "en": {
                "status": "published",
                "quality": {
                  "averageScore": 92,
                  "failedSegments": 0
                }
              }
            }
            """,
            CreatedAtUtc = DateTime.UtcNow
        };

        job.Outputs.Add(new TranscriptionJobOutput { JobId = job.Id, OutputType = "render_preview", FilePath = "outputs/job/render_preview.mp4" });
        job.Outputs.Add(new TranscriptionJobOutput { JobId = job.Id, OutputType = "scene_map", FilePath = "outputs/job/scene_map.json" });
        job.Outputs.Add(new TranscriptionJobOutput { JobId = job.Id, OutputType = "speaker_map", FilePath = "outputs/job/speaker_map.json" });
        job.Outputs.Add(new TranscriptionJobOutput { JobId = job.Id, OutputType = "lyric_alignment", FilePath = "outputs/job/lyric_alignment.json" });
        job.Outputs.Add(new TranscriptionJobOutput { JobId = job.Id, OutputType = "karaoke_plan", FilePath = "outputs/job/karaoke_plan.json" });
        job.Outputs.Add(new TranscriptionJobOutput { JobId = job.Id, OutputType = "video_muxed", FilePath = "outputs/job/video_muxed.mkv" });

        db.TranscriptionJobs.Add(job);
        await db.SaveChangesAsync();

        var settings = new PythonTranscriptionSettings
        {
            BaseUrl = "http://127.0.0.1:8001",
            InternalApiKey = "local_test_key",
            TimeoutMinutes = 480
        };

        var controller = new TranscriptionController(
            db,
            new FakeStorage(),
            CreatePythonClient("""{"service":"transcription"}""", settings),
            settings);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(
                    new ClaimsIdentity(
                    [
                        new Claim(ClaimTypes.NameIdentifier, "user-1")
                    ], "test"))
            }
        };
        controller.Url = new FakeUrlHelper();

        var action = await controller.GetJob(job.Id, CancellationToken.None);
        var ok = Assert.IsType<OkObjectResult>(action);
        var payload = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(
            JsonSerializer.Serialize(ok.Value, JsonOptions),
            JsonOptions)!;

        Assert.Equal("balanced", payload["timeoutProfileApplied"].GetString());
        Assert.Equal(480, payload["jobTimeoutMinutes"].GetInt32());
        Assert.Equal(90, payload["structuredTimeoutSeconds"].GetInt32());
        Assert.Equal(180, payload["styleTimeoutSeconds"].GetInt32());
        Assert.Equal("rendered", payload["previewModeApplied"].GetString());

        var qualitySummary = payload["qualitySummary"];
        Assert.True(qualitySummary.TryGetProperty("releaseGate", out var releaseGate));
        Assert.True(releaseGate.GetProperty("ready").GetBoolean());
    }

    [Fact]
    public async Task CreateJob_BlocksExecution_WhenSelectedModelIsNotInstalled()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString("N"))
            .Options;

        await using var db = new AppDbContext(options);

        var capabilitiesJson = """
        {
          "service": "transcription",
          "providers": [
            {
              "id": "ollama_project",
              "label": "Ollama do projeto",
              "type": "ollama",
              "available": true,
              "installedModels": ["qwen2.5vl:7b"],
              "downloadableModels": ["qwen2.5vl:32b"],
              "multimodalModels": ["qwen2.5vl:7b", "qwen2.5vl:32b", "qwen3-vl:30b-a3b-instruct-q4_K_M"],
              "defaultModel": "qwen2.5vl:7b"
            }
          ],
          "installedModelsByProvider": {
            "ollama_project": ["qwen2.5vl:7b"]
          },
          "downloadableModelsByProvider": {
            "ollama_project": ["qwen2.5vl:32b"]
          }
        }
        """;

        var settings = new PythonTranscriptionSettings
        {
            BaseUrl = "http://127.0.0.1:8001",
            InternalApiKey = "local_test_key",
            TimeoutMinutes = 480
        };

        var controller = new TranscriptionController(
            db,
            new FakeStorage(),
            CreatePythonClient(capabilitiesJson, settings),
            settings);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(
                    new ClaimsIdentity(
                    [
                        new Claim(ClaimTypes.NameIdentifier, "user-1")
                    ], "test"))
            }
        };

        var request = new TranscriptionController.CreateTranscriptionJobRequest
        {
            SourceType = "file_path",
            SourceValue = "C:/media/video.mkv",
            Task = "translate",
            AiEnhancementEnabled = true,
            AiProvider = "ollama_project",
            AiModel = "qwen2.5vl:32b",
            TargetLanguages = new List<string> { "pt-BR" }
        };

        var action = await controller.CreateJob(request, CancellationToken.None);
        var badRequest = Assert.IsType<BadRequestObjectResult>(action);
        var payload = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(
            JsonSerializer.Serialize(badRequest.Value, JsonOptions),
            JsonOptions)!;

        Assert.Contains("não está instalado", payload["message"].GetString(), StringComparison.OrdinalIgnoreCase);
    }

    private static PythonTranscriptionClient CreatePythonClient(string responseJson, PythonTranscriptionSettings settings)
    {
        var handler = new FakeHttpMessageHandler(responseJson);
        var httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri(settings.BaseUrl.TrimEnd('/') + "/")
        };

        return new PythonTranscriptionClient(
            httpClient,
            settings,
            NullLogger<PythonTranscriptionClient>.Instance);
    }

    private sealed class FakeHttpMessageHandler : HttpMessageHandler
    {
        private readonly string _responseJson;

        public FakeHttpMessageHandler(string responseJson)
        {
            _responseJson = responseJson;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(_responseJson, Encoding.UTF8, "application/json")
            });
        }
    }

    private sealed class FakeStorage : ILocalMediaStorage
    {
        public void EnsureDirectories()
        {
        }

        public Task<StoredMediaFile> SaveSourceUploadAsync(IFormFile file, string userId, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public string ResolveSourcePathForProcessing(string storedPath) => storedPath;

        public string ResolveManagedFilePath(string storedPath) => storedPath;

        public string NormalizeStoredPath(string storedPath) => storedPath.Replace("\\", "/");

        public string GetContentType(string pathOrFileName) => "application/octet-stream";
    }

    private sealed class FakeUrlHelper : IUrlHelper
    {
        public ActionContext ActionContext { get; } = new();

        public string? Action(UrlActionContext actionContext)
            => $"/fake/{actionContext.Action ?? "action"}";

        public string? Content(string? contentPath) => contentPath;

        public bool IsLocalUrl(string? url) => true;

        public string? Link(string? routeName, object? values) => $"/fake/{routeName ?? "link"}";

        public string? RouteUrl(UrlRouteContext routeContext)
            => $"/fake/{routeContext.RouteName ?? "route"}";
    }
}
