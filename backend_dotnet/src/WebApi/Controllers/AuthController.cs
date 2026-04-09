using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Infrastructure.Identity;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Tokens;

namespace WebApi.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private const string RefreshTokenProvider = "ProjectAuth";
    private const string RefreshTokenName = "RefreshToken";

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly UserManager<ApplicationUser> _userManager;
    private readonly IConfiguration _configuration;

    public AuthController(
        UserManager<ApplicationUser> userManager,
        IConfiguration configuration)
    {
        _userManager = userManager;
        _configuration = configuration;
    }

    [AllowAnonymous]
    [HttpPost("register")]
    public async Task<ActionResult<AuthSessionResponse>> Register([FromBody] RegisterRequest req)
    {
        if (!ModelState.IsValid)
            return ValidationProblem(ModelState);

        var email = req.Email.Trim().ToLowerInvariant();

        var existing = await _userManager.FindByEmailAsync(email);
        if (existing is not null)
            return Conflict(new { message = "Email já está em uso." });

        var user = new ApplicationUser
        {
            Email = email,
            UserName = email,
            DisplayName = email
        };

        var result = await _userManager.CreateAsync(user, req.Password);

        if (!result.Succeeded)
            return BadRequest(new
            {
                message = "Não foi possível criar o usuário.",
                errors = result.Errors.Select(e => e.Description).ToArray()
            });

        return Ok(await CreateSessionAsync(user));
    }

    [AllowAnonymous]
    [HttpPost("login")]
    public async Task<ActionResult<AuthSessionResponse>> Login([FromBody] LoginRequest req)
    {
        if (!ModelState.IsValid)
            return ValidationProblem(ModelState);

        var email = req.Email.Trim().ToLowerInvariant();
        var user = await _userManager.FindByEmailAsync(email);

        if (user is null)
            return Unauthorized(new { message = "Credenciais inválidas." });

        var validPassword = await _userManager.CheckPasswordAsync(user, req.Password);
        if (!validPassword)
            return Unauthorized(new { message = "Credenciais inválidas." });

        return Ok(await CreateSessionAsync(user));
    }

    [AllowAnonymous]
    [HttpPost("refresh")]
    public async Task<ActionResult<AuthSessionResponse>> Refresh([FromBody] RefreshRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.RefreshToken))
            return Unauthorized(new { message = "Refresh token inválido." });

        var validation = await ValidateRefreshTokenAsync(req.RefreshToken);
        if (validation.User is null)
            return Unauthorized(new { message = "Refresh token inválido ou expirado." });

        return Ok(await CreateSessionAsync(validation.User));
    }

    [AllowAnonymous]
    [HttpPost("logout")]
    public async Task<IActionResult> Logout([FromBody] LogoutRequest? req)
    {
        ApplicationUser? user = null;

        if (User.Identity?.IsAuthenticated == true)
        {
            user = await _userManager.GetUserAsync(User);
        }

        if (user is null && !string.IsNullOrWhiteSpace(req?.RefreshToken))
        {
            user = await FindUserByRefreshTokenAsync(req.RefreshToken!);
        }

        if (user is not null)
        {
            await RevokeRefreshTokenAsync(user);
        }

        return NoContent();
    }

    [Authorize]
    [HttpGet("me")]
    public async Task<ActionResult<MeResponse>> Me()
    {
        var user = await _userManager.GetUserAsync(User);
        if (user is null) return Unauthorized();

        return Ok(new MeResponse(
            user.Email ?? "",
            user.DisplayName ?? user.UserName ?? ""
        ));
    }

    [Authorize]
    [HttpPut("me")]
    public async Task<ActionResult<MeResponse>> UpdateMe([FromBody] UpdateMeRequest req)
    {
        if (!ModelState.IsValid)
            return ValidationProblem(ModelState);

        var user = await _userManager.GetUserAsync(User);
        if (user is null) return Unauthorized();

        var email = req.Email.Trim().ToLowerInvariant();
        var name = req.Name.Trim();

        var existing = await _userManager.FindByEmailAsync(email);
        if (existing is not null && existing.Id != user.Id)
            return Conflict(new { message = "Email já está em uso." });

        user.DisplayName = name;

        if (!string.Equals(user.Email, email, StringComparison.OrdinalIgnoreCase))
        {
            user.Email = email;
            user.UserName = email;
            user.EmailConfirmed = false;
        }

        var result = await _userManager.UpdateAsync(user);

        if (!result.Succeeded)
            return BadRequest(new
            {
                message = "Não foi possível atualizar o perfil.",
                errors = result.Errors.Select(e => e.Description).ToArray()
            });

        return Ok(new MeResponse(
            user.Email ?? "",
            user.DisplayName ?? user.UserName ?? ""
        ));
    }

    [Authorize]
    [HttpPost("change-password")]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequest req)
    {
        if (!ModelState.IsValid)
            return ValidationProblem(ModelState);

        var user = await _userManager.GetUserAsync(User);
        if (user is null) return Unauthorized();

        var result = await _userManager.ChangePasswordAsync(
            user,
            req.CurrentPassword,
            req.NewPassword
        );

        if (!result.Succeeded)
            return BadRequest(new
            {
                message = "Não foi possível alterar a senha.",
                errors = result.Errors.Select(e => e.Description).ToArray()
            });

        return NoContent();
    }

    private async Task<AuthSessionResponse> CreateSessionAsync(ApplicationUser user)
    {
        var accessToken = GenerateJwt(user);
        var refreshToken = await IssueRefreshTokenAsync(user);
        return new AuthSessionResponse(accessToken.Token, refreshToken, accessToken.ExpiresAtUtc);
    }

    private JwtToken GenerateJwt(ApplicationUser user)
    {
        var jwt = _configuration.GetSection("Jwt");
        var issuer = jwt["Issuer"] ?? throw new InvalidOperationException("Jwt:Issuer não configurado.");
        var audience = jwt["Audience"] ?? throw new InvalidOperationException("Jwt:Audience não configurado.");
        var key = jwt["Key"] ?? throw new InvalidOperationException("Jwt:Key não configurado.");
        var accessTokenMinutes = int.TryParse(jwt["AccessTokenMinutes"], out var minutes) ? minutes : 60;

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id),
            new(JwtRegisteredClaimNames.Email, user.Email ?? ""),
            new(ClaimTypes.NameIdentifier, user.Id),
            new(ClaimTypes.Email, user.Email ?? ""),
            new(ClaimTypes.Name, user.DisplayName ?? user.UserName ?? user.Email ?? ""),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };

        var signingKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key));
        var credentials = new SigningCredentials(signingKey, SecurityAlgorithms.HmacSha256);
        var expiresAtUtc = DateTime.UtcNow.AddMinutes(accessTokenMinutes);

        var token = new JwtSecurityToken(
            issuer: issuer,
            audience: audience,
            claims: claims,
            notBefore: DateTime.UtcNow,
            expires: expiresAtUtc,
            signingCredentials: credentials
        );

        return new JwtToken(new JwtSecurityTokenHandler().WriteToken(token), expiresAtUtc);
    }

    private async Task<string> IssueRefreshTokenAsync(ApplicationUser user)
    {
        var secret = GenerateRefreshSecret();
        var payload = new StoredRefreshToken(
            SecretHash: ComputeSha256(secret),
            ExpiresAtUtc: DateTime.UtcNow.AddDays(GetRefreshTokenLifetimeDays()),
            CreatedAtUtc: DateTime.UtcNow);

        await _userManager.SetAuthenticationTokenAsync(
            user,
            RefreshTokenProvider,
            RefreshTokenName,
            JsonSerializer.Serialize(payload, JsonOptions));

        return $"{user.Id}.{secret}";
    }

    private async Task<(ApplicationUser? User, StoredRefreshToken? Token)> ValidateRefreshTokenAsync(string refreshToken)
    {
        var parts = SplitRefreshToken(refreshToken);
        if (parts is null)
            return (null, null);

        var user = await _userManager.FindByIdAsync(parts.Value.UserId);
        if (user is null)
            return (null, null);

        var rawPayload = await _userManager.GetAuthenticationTokenAsync(user, RefreshTokenProvider, RefreshTokenName);
        if (string.IsNullOrWhiteSpace(rawPayload))
            return (null, null);

        StoredRefreshToken? payload;
        try
        {
            payload = JsonSerializer.Deserialize<StoredRefreshToken>(rawPayload, JsonOptions);
        }
        catch
        {
            await RevokeRefreshTokenAsync(user);
            return (null, null);
        }

        if (payload is null)
        {
            await RevokeRefreshTokenAsync(user);
            return (null, null);
        }

        if (payload.ExpiresAtUtc <= DateTime.UtcNow)
        {
            await RevokeRefreshTokenAsync(user);
            return (null, null);
        }

        var providedHash = ComputeSha256(parts.Value.Secret);
        if (!string.Equals(payload.SecretHash, providedHash, StringComparison.OrdinalIgnoreCase))
            return (null, null);

        return (user, payload);
    }

    private async Task<ApplicationUser?> FindUserByRefreshTokenAsync(string refreshToken)
    {
        var parts = SplitRefreshToken(refreshToken);
        if (parts is null)
            return null;

        var user = await _userManager.FindByIdAsync(parts.Value.UserId);
        if (user is null)
            return null;

        var current = await ValidateRefreshTokenAsync(refreshToken);
        return current.User?.Id == user.Id ? user : null;
    }

    private async Task RevokeRefreshTokenAsync(ApplicationUser user)
    {
        await _userManager.RemoveAuthenticationTokenAsync(user, RefreshTokenProvider, RefreshTokenName);
    }

    private int GetRefreshTokenLifetimeDays()
    {
        var jwt = _configuration.GetSection("Jwt");
        var configured = int.TryParse(jwt["RefreshTokenDays"], out var days) ? days : 14;
        return Math.Max(configured, 1);
    }

    private static (string UserId, string Secret)? SplitRefreshToken(string refreshToken)
    {
        var normalized = (refreshToken ?? string.Empty).Trim();
        var separatorIndex = normalized.IndexOf('.');
        if (separatorIndex <= 0 || separatorIndex == normalized.Length - 1)
            return null;

        var userId = normalized[..separatorIndex];
        var secret = normalized[(separatorIndex + 1)..];
        if (string.IsNullOrWhiteSpace(userId) || string.IsNullOrWhiteSpace(secret))
            return null;

        return (userId, secret);
    }

    private static string GenerateRefreshSecret()
    {
        var bytes = RandomNumberGenerator.GetBytes(48);
        return Base64UrlEncoder.Encode(bytes);
    }

    private static string ComputeSha256(string value)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(bytes);
    }

    private sealed record JwtToken(string Token, DateTime ExpiresAtUtc);
    private sealed record StoredRefreshToken(string SecretHash, DateTime ExpiresAtUtc, DateTime CreatedAtUtc);
}

public sealed record RegisterRequest(string Email, string Password);
public sealed record LoginRequest(string Email, string Password);
public sealed record RefreshRequest(string RefreshToken);
public sealed record LogoutRequest(string? RefreshToken);
public sealed record UpdateMeRequest(string Name, string Email);
public sealed record ChangePasswordRequest(string CurrentPassword, string NewPassword);
public sealed record MeResponse(string Email, string Name);
public sealed record AuthSessionResponse(string AccessToken, string RefreshToken, DateTime AccessTokenExpiresAtUtc);
