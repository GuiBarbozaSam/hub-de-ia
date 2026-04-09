using System.Text.Json;
using Infrastructure.Persistence;
using Infrastructure.Transcription;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace WebApi.Controllers;

[ApiController]
[Route("internal/transcription/jobs")]
[AllowAnonymous]
public sealed class InternalTranscriptionController : ControllerBase
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly AppDbContext _db;
    private readonly PythonTranscriptionSettings _settings;

    public InternalTranscriptionController(AppDbContext db, PythonTranscriptionSettings settings)
    {
        _db = db;
        _settings = settings;
    }

    [HttpPost("{id:guid}/progress")]
    public async Task<IActionResult> UpdateProgress(
        [FromRoute] Guid id,
        [FromBody] UpdateTranscriptionJobProgressRequest request,
        [FromHeader(Name = "X-Internal-Api-Key")] string? internalApiKey,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(_settings.InternalApiKey) ||
            !string.Equals(_settings.InternalApiKey.Trim(), (internalApiKey ?? string.Empty).Trim(), StringComparison.Ordinal))
        {
            return Unauthorized(new { message = "Chave interna inválida." });
        }

        var job = await _db.TranscriptionJobs.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (job is null)
        {
            return NotFound();
        }

        job.ProgressPercent = Math.Clamp(request.ProgressPercent, 0, 100);
        job.CurrentStage = string.IsNullOrWhiteSpace(request.CurrentStage)
            ? job.CurrentStage
            : request.CurrentStage.Trim();
        job.CurrentPass = Math.Max(0, request.CurrentPass);
        job.TotalPasses = Math.Max(job.TotalPasses, Math.Max(0, request.TotalPasses));

        if (!string.IsNullOrWhiteSpace(request.StyleSource))
            job.StyleSource = request.StyleSource.Trim();

        if (request.QualitySummary is not null)
            job.QualitySummaryJson = JsonSerializer.Serialize(request.QualitySummary, JsonOptions);

        if (request.TranslationStatuses is not null)
            job.TranslationStatusesJson = JsonSerializer.Serialize(request.TranslationStatuses, JsonOptions);

        if (request.CapabilityProfile is not null)
            job.CapabilityProfileJson = JsonSerializer.Serialize(request.CapabilityProfile, JsonOptions);

        if (!string.IsNullOrWhiteSpace(request.ErrorMessage))
            job.ErrorMessage = request.ErrorMessage.Trim();

        await _db.SaveChangesAsync(ct);
        return Ok(new { ok = true });
    }

    public sealed class UpdateTranscriptionJobProgressRequest
    {
        public int ProgressPercent { get; set; }
        public string? CurrentStage { get; set; }
        public int CurrentPass { get; set; }
        public int TotalPasses { get; set; }
        public object? QualitySummary { get; set; }
        public object? TranslationStatuses { get; set; }
        public string? StyleSource { get; set; }
        public object? CapabilityProfile { get; set; }
        public string? ErrorMessage { get; set; }
    }
}
