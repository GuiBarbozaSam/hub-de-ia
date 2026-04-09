namespace Infrastructure.Storage;

public sealed class StoredMediaFile
{
    public string OriginalFileName { get; init; } = "";
    public string StoredFileName { get; init; } = "";
    public string RelativePath { get; init; } = "";
    public string AbsolutePath { get; init; } = "";
    public long SizeBytes { get; init; }
    public string ContentType { get; init; } = "application/octet-stream";
}