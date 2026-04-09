using System.Text;
using Infrastructure.Identity;
using Infrastructure.Persistence;
using Infrastructure.Storage;
using Infrastructure.Transcription;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi;
using Microsoft.Extensions.Hosting;

var builder = WebApplication.CreateBuilder(args);

if (builder.Environment.IsDevelopment())
{
    builder.Configuration.AddJsonFile("appsettings.Development.local.json", optional: true, reloadOnChange: true);
}

builder.Services.Configure<HostOptions>(options =>
{
    options.BackgroundServiceExceptionBehavior = BackgroundServiceExceptionBehavior.Ignore;
    options.ShutdownTimeout = TimeSpan.FromSeconds(30);
});

builder.Services.AddControllers();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo { Title = "Hub de IA API", Version = "v1" });

    const string schemeId = "bearer";
    options.AddSecurityDefinition(schemeId, new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http,
        Scheme = schemeId,
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Name = "Authorization",
        Description = "Digite: Bearer {seu_token}"
    });

    options.AddSecurityRequirement(document => new OpenApiSecurityRequirement
    {
        [new OpenApiSecuritySchemeReference(schemeId, document)] = []
    });
});

var pySection = builder.Configuration.GetSection("PythonTranscription");
var pySettings = pySection.Get<PythonTranscriptionSettings>() ?? new PythonTranscriptionSettings();
if (string.IsNullOrWhiteSpace(pySettings.BaseUrl))
    throw new InvalidOperationException("PythonTranscription:BaseUrl não configurado.");

builder.Services.AddSingleton(pySettings);
builder.Services.AddHttpClient<PythonTranscriptionClient>((sp, client) =>
{
    var settings = sp.GetRequiredService<PythonTranscriptionSettings>();
    client.BaseAddress = new Uri(settings.BaseUrl.TrimEnd('/') + "/");
    client.Timeout = settings.TimeoutMinutes <= 0 ? Timeout.InfiniteTimeSpan : TimeSpan.FromMinutes(settings.TimeoutMinutes);
});

builder.Services.AddHostedService<TranscriptionJobWorker>();

var storageSection = builder.Configuration.GetSection("TranscriptionStorage");
var storageSettings = storageSection.Get<LocalMediaStorageSettings>() ?? new LocalMediaStorageSettings();
var maxUploadBytes = storageSettings.MaxUploadMb * 1024L * 1024L;

builder.Services.AddSingleton(storageSettings);
builder.Services.AddSingleton<ILocalMediaStorage, LocalMediaStorage>();

builder.WebHost.ConfigureKestrel(options => { options.Limits.MaxRequestBodySize = maxUploadBytes; });
builder.Services.Configure<FormOptions>(options => { options.MultipartBodyLengthLimit = maxUploadBytes; });
builder.Services.Configure<IISServerOptions>(options => { options.MaxRequestBodySize = maxUploadBytes; });

var cs = builder.Configuration.GetConnectionString("Default") ?? throw new InvalidOperationException("ConnectionStrings:Default não configurada.");
builder.Services.AddDbContext<AppDbContext>(opt => opt.UseNpgsql(cs));

builder.Services.AddIdentityCore<ApplicationUser>(options =>
{
    options.User.RequireUniqueEmail = true;
    options.Password.RequiredLength = 8;
    options.Password.RequireNonAlphanumeric = false;
})
.AddRoles<IdentityRole>()
.AddEntityFrameworkStores<AppDbContext>()
.AddSignInManager()
.AddDefaultTokenProviders();

var jwt = builder.Configuration.GetSection("Jwt");
var key = jwt["Key"] ?? throw new InvalidOperationException("Jwt:Key não configurado.");

ValidateDevelopmentSecrets(builder.Environment, cs, key, pySettings.InternalApiKey);

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = jwt["Issuer"],
        ValidAudience = jwt["Audience"],
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)),
        ClockSkew = TimeSpan.FromSeconds(30),
    };
});

builder.Services.AddAuthorization();

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    scope.ServiceProvider.GetRequiredService<ILocalMediaStorage>().EnsureDirectories();
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c => c.SwaggerEndpoint("/swagger/v1/swagger.json", "Hub de IA API v1"));
}

if (!app.Environment.IsDevelopment())
    app.UseHttpsRedirection();

app.Use(async (ctx, next) =>
{
    var hasAuthHeader = !string.IsNullOrWhiteSpace(ctx.Request.Headers.Authorization.ToString());
    Console.WriteLine($"[{DateTime.UtcNow:O}] [{ctx.Request.Method}] {ctx.Request.Path} | AuthHeaderPresent: {hasAuthHeader}");
    await next();
    Console.WriteLine($"[{DateTime.UtcNow:O}] [{ctx.Request.Method}] {ctx.Request.Path} => {ctx.Response.StatusCode}");
});

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapGet("/health", () => Results.Ok(new { ok = true, service = "WebApi", pythonTranscriptionBaseUrl = pySettings.BaseUrl, pythonTimeoutMinutes = pySettings.TimeoutMinutes }));
app.Run();

static void ValidateDevelopmentSecrets(IHostEnvironment environment, string connectionString, string jwtKey, string? internalApiKey)
{
    if (!environment.IsDevelopment())
    {
        return;
    }

    var placeholderErrors = new List<string>();

    if (ContainsPlaceholder(connectionString))
    {
        placeholderErrors.Add("ConnectionStrings:Default");
    }

    if (ContainsPlaceholder(jwtKey) || jwtKey.Trim().Length < 32)
    {
        placeholderErrors.Add("Jwt:Key");
    }

    if (ContainsPlaceholder(internalApiKey))
    {
        placeholderErrors.Add("PythonTranscription:InternalApiKey");
    }

    if (placeholderErrors.Count == 0)
    {
        return;
    }

    throw new InvalidOperationException(
        "Configuração local insegura ou incompleta. Preencha backend_dotnet/src/WebApi/appsettings.Development.local.json com valores reais para: "
        + string.Join(", ", placeholderErrors)
        + ". Use o arquivo appsettings.Development.local.example.json como base.");
}

static bool ContainsPlaceholder(string? value)
{
    var normalized = (value ?? string.Empty).Trim().ToLowerInvariant();
    if (string.IsNullOrWhiteSpace(normalized))
    {
        return true;
    }

    return normalized.Contains("change_me")
        || normalized.Contains("replace_with")
        || normalized.Contains("troque")
        || normalized.Contains("dev_only");
}
