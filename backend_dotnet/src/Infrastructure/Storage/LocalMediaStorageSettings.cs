namespace Infrastructure.Storage;

public sealed class LocalMediaStorageSettings
{
    public string RootPath { get; set; } = "";

    public string UploadsFolderName { get; set; } = "uploads";

    public string OutputsFolderName { get; set; } = "outputs";

    public int MaxUploadMb { get; set; } = 1024;

    public string[] AllowedExtensions { get; set; } =
    [
        ".mp4", ".mov", ".mkv", ".avi", ".webm",
        ".mp3", ".wav", ".m4a", ".aac", ".flac", ".ogg"
    ];
}