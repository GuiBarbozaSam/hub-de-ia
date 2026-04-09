using System;

namespace Domain.Entities;

public class TranscriptionJobOutput
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid JobId { get; set; }
    public TranscriptionJob? Job { get; set; }

    public string OutputType { get; set; } = "text"; // text | srt | vtt | video_burned
    public string? ContentText { get; set; }
    public string? FilePath { get; set; }

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}