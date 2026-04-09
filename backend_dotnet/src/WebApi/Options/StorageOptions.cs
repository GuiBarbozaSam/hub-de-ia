namespace WebApi.Options;

public sealed class StorageOptions
{
    public const string SectionName = "Storage";

    public string UploadsRoot { get; set; } = string.Empty;
}