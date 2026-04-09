namespace Infrastructure.Transcription;

public sealed class PythonTranscriptionSettings
{
    public string BaseUrl { get; set; } = "http://127.0.0.1:8001";
    public string CallbackBaseUrl { get; set; } = "http://127.0.0.1:5045";
    public string InternalApiKey { get; set; } = "change_me_internal_api_key";
    public int TimeoutMinutes { get; set; } = 480;
    public string JobsRoute { get; set; } = "api/v1/transcription/jobs/run";
}
