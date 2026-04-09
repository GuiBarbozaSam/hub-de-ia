using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace Infrastructure.Transcription;

public sealed class PythonTranscriptionClient
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };
    private static readonly TimeSpan CapabilitiesCacheTtl = TimeSpan.FromSeconds(30);

    private readonly HttpClient _httpClient;
    private readonly PythonTranscriptionSettings _settings;
    private readonly ILogger<PythonTranscriptionClient> _logger;
    private readonly SemaphoreSlim _capabilitiesLock = new(1, 1);
    private PythonTranscriptionCapabilities? _capabilitiesCache;
    private DateTimeOffset _capabilitiesCachedAtUtc = DateTimeOffset.MinValue;

    public PythonTranscriptionClient(
        HttpClient httpClient,
        PythonTranscriptionSettings settings,
        ILogger<PythonTranscriptionClient> logger)
    {
        _httpClient = httpClient;
        _settings = settings;
        _logger = logger;
    }

    public async Task<PythonTranscriptionResult> RunAsync(
        PythonTranscriptionRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        var route = (_settings.JobsRoute ?? string.Empty).Trim().TrimStart('/');

        if (string.IsNullOrWhiteSpace(route))
        {
            throw new InvalidOperationException("PythonTranscriptionSettings.JobsRoute não configurado.");
        }

        if (string.Equals(request.SourceType, "file_path", StringComparison.OrdinalIgnoreCase)
            && string.IsNullOrWhiteSpace(request.SourceValue))
        {
            throw new InvalidOperationException("SourceValue é obrigatório para source_type=file_path.");
        }

        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, route);
        httpRequest.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        if (!string.IsNullOrWhiteSpace(_settings.InternalApiKey))
        {
            httpRequest.Headers.Add("X-Internal-Api-Key", _settings.InternalApiKey);
        }

        var payload = JsonSerializer.Serialize(request, JsonOptions);
        httpRequest.Content = new StringContent(payload, Encoding.UTF8, "application/json");

        _logger.LogInformation(
            "Enviando job para o serviço Python. BaseAddress: {BaseAddress}, Route: {Route}, SourceType: {SourceType}, SourceValue: {SourceValue}, Model: {Model}, Task: {Task}",
            _httpClient.BaseAddress?.ToString(),
            route,
            request.SourceType,
            request.SourceValue,
            request.Model,
            request.Task);

        using var response = await _httpClient.SendAsync(
            httpRequest,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);

        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogWarning(
                "Serviço Python retornou erro HTTP {StatusCode}. Body: {Body}",
                (int)response.StatusCode,
                Truncate(responseBody, 4000));

            throw new InvalidOperationException(
                $"Falha ao chamar o serviço Python. HTTP {(int)response.StatusCode}. Body: {Truncate(responseBody, 4000)}");
        }

        PythonTranscriptionResult? result;
        try
        {
            result = JsonSerializer.Deserialize<PythonTranscriptionResult>(responseBody, JsonOptions);
        }
        catch (JsonException ex)
        {
            _logger.LogError(
                ex,
                "Resposta JSON inválida do serviço Python. Body: {Body}",
                Truncate(responseBody, 4000));

            throw new InvalidOperationException(
                $"Resposta inválida do serviço Python. Body: {Truncate(responseBody, 4000)}");
        }

        if (result is null)
        {
            throw new InvalidOperationException(
                $"Resposta nula do serviço Python. Body: {Truncate(responseBody, 4000)}");
        }

        _logger.LogInformation(
            "Resposta recebida do Python. Status: {Status}, LanguageDetected: {LanguageDetected}, DurationSeconds: {DurationSeconds}",
            result.Status,
            result.LanguageDetected,
            result.DurationSeconds);

        return result;
    }

    public async Task<PythonTranscriptionCapabilities> GetCapabilitiesAsync(
        CancellationToken cancellationToken = default)
    {
        if (_capabilitiesCache is not null &&
            (DateTimeOffset.UtcNow - _capabilitiesCachedAtUtc) <= CapabilitiesCacheTtl)
        {
            return _capabilitiesCache;
        }

        await _capabilitiesLock.WaitAsync(cancellationToken);
        try
        {
            if (_capabilitiesCache is not null &&
                (DateTimeOffset.UtcNow - _capabilitiesCachedAtUtc) <= CapabilitiesCacheTtl)
            {
                return _capabilitiesCache;
            }

        using var httpRequest = new HttpRequestMessage(HttpMethod.Get, "api/v1/transcription/capabilities");
        httpRequest.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        if (!string.IsNullOrWhiteSpace(_settings.InternalApiKey))
        {
            httpRequest.Headers.Add("X-Internal-Api-Key", _settings.InternalApiKey);
        }

        using var response = await _httpClient.SendAsync(
            httpRequest,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);

        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"Falha ao obter capabilities do serviço Python. HTTP {(int)response.StatusCode}. Body: {Truncate(responseBody, 4000)}");
        }

        var result = JsonSerializer.Deserialize<PythonTranscriptionCapabilities>(responseBody, JsonOptions);
        if (result is null)
        {
            throw new InvalidOperationException(
                $"Capabilities nulas do serviço Python. Body: {Truncate(responseBody, 4000)}");
        }

            _capabilitiesCache = result;
            _capabilitiesCachedAtUtc = DateTimeOffset.UtcNow;
        return result;
        }
        finally
        {
            _capabilitiesLock.Release();
        }
    }

    public async Task<Dictionary<string, object?>> StartModelDownloadAsync(
        string provider,
        string model,
        CancellationToken cancellationToken = default)
    {
        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, "api/v1/transcription/models/download");
        httpRequest.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        if (!string.IsNullOrWhiteSpace(_settings.InternalApiKey))
        {
            httpRequest.Headers.Add("X-Internal-Api-Key", _settings.InternalApiKey);
        }

        httpRequest.Content = new StringContent(
            JsonSerializer.Serialize(new { provider, model }, JsonOptions),
            Encoding.UTF8,
            "application/json");

        using var response = await _httpClient.SendAsync(
            httpRequest,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);

        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"Falha ao iniciar download do modelo no serviço Python. HTTP {(int)response.StatusCode}. Body: {Truncate(responseBody, 4000)}");
        }

        InvalidateCapabilitiesCache();
        var decoded = JsonSerializer.Deserialize<Dictionary<string, object?>>(responseBody, JsonOptions);
        return decoded ?? new Dictionary<string, object?>();
    }

    public async Task<Dictionary<string, object?>> GetModelDownloadStatusAsync(
        string downloadId,
        CancellationToken cancellationToken = default)
    {
        using var httpRequest = new HttpRequestMessage(HttpMethod.Get, $"api/v1/transcription/models/downloads/{Uri.EscapeDataString(downloadId)}");
        httpRequest.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        if (!string.IsNullOrWhiteSpace(_settings.InternalApiKey))
        {
            httpRequest.Headers.Add("X-Internal-Api-Key", _settings.InternalApiKey);
        }

        using var response = await _httpClient.SendAsync(
            httpRequest,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);

        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"Falha ao obter status do download do modelo no serviço Python. HTTP {(int)response.StatusCode}. Body: {Truncate(responseBody, 4000)}");
        }

        var decoded = JsonSerializer.Deserialize<Dictionary<string, object?>>(responseBody, JsonOptions);
        if (decoded is not null &&
            decoded.TryGetValue("status", out var status) &&
            string.Equals(Convert.ToString(status), "completed", StringComparison.OrdinalIgnoreCase))
        {
            InvalidateCapabilitiesCache();
        }
        return decoded ?? new Dictionary<string, object?>();
    }

    private void InvalidateCapabilitiesCache()
    {
        _capabilitiesCache = null;
        _capabilitiesCachedAtUtc = DateTimeOffset.MinValue;
    }

    private static string Truncate(string? value, int maxLength)
    {
        if (string.IsNullOrEmpty(value) || value.Length <= maxLength)
        {
            return value ?? string.Empty;
        }

        return value[..maxLength] + "...";
    }
}



