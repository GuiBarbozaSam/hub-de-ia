using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using System.Text.RegularExpressions;

namespace Infrastructure.Storage;

public sealed class LocalMediaStorage : ILocalMediaStorage
{
    private static readonly Regex UnsafePathSegmentRegex = new("[^a-zA-Z0-9_-]", RegexOptions.Compiled);

    private static readonly Dictionary<string, string> ContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        [".txt"] = "text/plain; charset=utf-8",
        [".srt"] = "text/plain; charset=utf-8",
        [".vtt"] = "text/vtt; charset=utf-8",
        [".mp4"] = "video/mp4",
        [".mov"] = "video/quicktime",
        [".mkv"] = "video/x-matroska",
        [".avi"] = "video/x-msvideo",
        [".webm"] = "video/webm",
        [".mp3"] = "audio/mpeg",
        [".wav"] = "audio/wav",
        [".m4a"] = "audio/mp4",
        [".aac"] = "audio/aac",
        [".flac"] = "audio/flac",
        [".ogg"] = "audio/ogg"
    };

    private readonly LocalMediaStorageSettings _settings;
    private readonly ILogger<LocalMediaStorage> _logger;
    private readonly string _rootPath;
    private readonly string _rootPathWithSeparator;
    private readonly string _uploadsRoot;
    private readonly string _outputsRoot;
    private readonly HashSet<string> _allowedExtensions;

    public LocalMediaStorage(
        IWebHostEnvironment environment,
        LocalMediaStorageSettings settings,
        ILogger<LocalMediaStorage> logger)
    {
        ArgumentNullException.ThrowIfNull(environment);
        ArgumentNullException.ThrowIfNull(settings);

        _settings = settings;
        _logger = logger;

        var configuredRoot = string.IsNullOrWhiteSpace(settings.RootPath)
            ? Path.Combine(environment.ContentRootPath, "storage", "transcription")
            : settings.RootPath;

        _rootPath = NormalizeDirectoryPath(configuredRoot);
        _rootPathWithSeparator = EnsureTrailingSeparator(_rootPath);

        var uploadsFolderName = string.IsNullOrWhiteSpace(settings.UploadsFolderName)
            ? "uploads"
            : settings.UploadsFolderName.Trim();

        var outputsFolderName = string.IsNullOrWhiteSpace(settings.OutputsFolderName)
            ? "outputs"
            : settings.OutputsFolderName.Trim();

        _uploadsRoot = NormalizeDirectoryPath(Path.Combine(_rootPath, uploadsFolderName));
        _outputsRoot = NormalizeDirectoryPath(Path.Combine(_rootPath, outputsFolderName));

        _allowedExtensions = new HashSet<string>(
            (settings.AllowedExtensions ?? [])
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Select(NormalizeExtension),
            StringComparer.OrdinalIgnoreCase);

        if (_allowedExtensions.Count == 0)
        {
            throw new InvalidOperationException("Nenhuma extensão permitida foi configurada para o storage.");
        }
    }

    public void EnsureDirectories()
    {
        Directory.CreateDirectory(_rootPath);
        Directory.CreateDirectory(_uploadsRoot);
        Directory.CreateDirectory(_outputsRoot);

        _logger.LogInformation(
            "Storage inicializado. Root: {Root}, Uploads: {Uploads}, Outputs: {Outputs}",
            _rootPath,
            _uploadsRoot,
            _outputsRoot);
    }

    public async Task<StoredMediaFile> SaveSourceUploadAsync(
        IFormFile file,
        string userId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(file);

        if (file.Length <= 0)
        {
            throw new InvalidOperationException("O arquivo enviado está vazio.");
        }

        var maxBytes = _settings.MaxUploadMb * 1024L * 1024L;
        if (_settings.MaxUploadMb > 0 && file.Length > maxBytes)
        {
            throw new InvalidOperationException(
                $"O arquivo excede o limite configurado de {_settings.MaxUploadMb} MB.");
        }

        var originalFileName = Path.GetFileName(file.FileName ?? string.Empty);
        var extension = NormalizeExtension(Path.GetExtension(originalFileName));

        if (string.IsNullOrWhiteSpace(extension) || !_allowedExtensions.Contains(extension))
        {
            throw new InvalidOperationException(
                $"Extensão não permitida. Permitidas: {string.Join(", ", _allowedExtensions.OrderBy(x => x))}");
        }

        var safeUserId = MakeSafePathSegment(userId);
        var utcNow = DateTime.UtcNow;
        var datePath = Path.Combine(
            utcNow.ToString("yyyy"),
            utcNow.ToString("MM"),
            utcNow.ToString("dd"));

        var storedFileName = $"{Guid.NewGuid():N}{extension}";
        var absoluteDirectory = EnsureInsideRoot(Path.Combine(_uploadsRoot, safeUserId, datePath));
        Directory.CreateDirectory(absoluteDirectory);

        var absolutePath = EnsureInsideRoot(Path.Combine(absoluteDirectory, storedFileName));

        await using var destination = new FileStream(
            absolutePath,
            new FileStreamOptions
            {
                Mode = FileMode.CreateNew,
                Access = FileAccess.Write,
                Share = FileShare.None,
                BufferSize = 1024 * 128,
                Options = FileOptions.Asynchronous | FileOptions.SequentialScan
            });

        await file.CopyToAsync(destination, cancellationToken);
        await destination.FlushAsync(cancellationToken);

        if (!File.Exists(absolutePath))
        {
            throw new IOException($"Falha ao persistir o upload em disco: {absolutePath}");
        }

        var relativePath = ToRelativeStoragePath(absolutePath);

        _logger.LogInformation(
            "Upload salvo com sucesso. Original: {OriginalFileName}, RelativePath: {RelativePath}, SizeBytes: {SizeBytes}",
            originalFileName,
            relativePath,
            file.Length);

        return new StoredMediaFile
        {
            OriginalFileName = originalFileName,
            StoredFileName = storedFileName,
            RelativePath = relativePath,
            AbsolutePath = absolutePath,
            SizeBytes = file.Length,
            ContentType = GetContentType(absolutePath)
        };
    }

    public string ResolveSourcePathForProcessing(string storedPath)
    {
        if (string.IsNullOrWhiteSpace(storedPath))
        {
            throw new InvalidOperationException("Caminho da origem não informado.");
        }

        if (Path.IsPathRooted(storedPath))
        {
            return EnsureInsideRoot(storedPath);
        }

        return EnsureInsideRoot(Path.Combine(_rootPath, storedPath));
    }

    public string ResolveManagedFilePath(string storedPath)
    {
        if (string.IsNullOrWhiteSpace(storedPath))
        {
            throw new InvalidOperationException("Caminho do arquivo não informado.");
        }

        if (Path.IsPathRooted(storedPath))
        {
            return EnsureInsideRoot(storedPath);
        }

        return EnsureInsideRoot(Path.Combine(_rootPath, storedPath));
    }

    public string NormalizeStoredPath(string storedPath)
    {
        if (string.IsNullOrWhiteSpace(storedPath))
        {
            return storedPath;
        }

        if (!Path.IsPathRooted(storedPath))
        {
            return storedPath.Replace('\\', '/');
        }

        var full = Path.GetFullPath(storedPath);

        if (!IsInsideRoot(full))
        {
            return storedPath;
        }

        return ToRelativeStoragePath(full);
    }

    public string GetContentType(string pathOrFileName)
    {
        var ext = NormalizeExtension(Path.GetExtension(pathOrFileName));

        return ContentTypes.TryGetValue(ext, out var contentType)
            ? contentType
            : "application/octet-stream";
    }

    private string EnsureInsideRoot(string path)
    {
        var full = Path.GetFullPath(path);

        if (!IsInsideRoot(full))
        {
            throw new InvalidOperationException("Tentativa de acessar arquivo fora da raiz de storage.");
        }

        return full;
    }

    private bool IsInsideRoot(string fullPath)
    {
        var normalized = Path.GetFullPath(fullPath);
        return normalized.Equals(_rootPath, StringComparison.OrdinalIgnoreCase)
            || normalized.StartsWith(_rootPathWithSeparator, StringComparison.OrdinalIgnoreCase);
    }

    private string ToRelativeStoragePath(string absolutePath)
    {
        var full = EnsureInsideRoot(absolutePath);
        var relative = Path.GetRelativePath(_rootPath, full);
        return relative.Replace('\\', '/');
    }

    private static string MakeSafePathSegment(string value)
    {
        var safe = UnsafePathSegmentRegex.Replace(value ?? string.Empty, "");
        return string.IsNullOrWhiteSpace(safe) ? "anonymous" : safe;
    }

    private static string NormalizeExtension(string extension)
    {
        if (string.IsNullOrWhiteSpace(extension))
        {
            return string.Empty;
        }

        var value = extension.Trim();
        return value.StartsWith('.') ? value.ToLowerInvariant() : $".{value.ToLowerInvariant()}";
    }

    private static string NormalizeDirectoryPath(string path)
    {
        return Path.GetFullPath(path.Trim());
    }

    private static string EnsureTrailingSeparator(string path)
    {
        return Path.EndsInDirectorySeparator(path) ? path : path + Path.DirectorySeparatorChar;
    }
}