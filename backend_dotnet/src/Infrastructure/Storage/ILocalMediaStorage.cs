using Microsoft.AspNetCore.Http;

namespace Infrastructure.Storage;

public interface ILocalMediaStorage
{
    void EnsureDirectories();

    Task<StoredMediaFile> SaveSourceUploadAsync(
        IFormFile file,
        string userId,
        CancellationToken cancellationToken = default);

    string ResolveSourcePathForProcessing(string storedPath);

    string ResolveManagedFilePath(string storedPath);

    string NormalizeStoredPath(string storedPath);

    string GetContentType(string pathOrFileName);
}