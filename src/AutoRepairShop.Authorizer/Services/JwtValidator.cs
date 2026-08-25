using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.IdentityModel.Tokens;
using AutoRepairShop.Authorizer.Models;
using System.Text;

namespace AutoRepairShop.Authorizer.Services;

public class JwtValidator : IJwtValidator
{
    private readonly SecretsManagerService _secretsManager;
    private readonly JwtSecurityTokenHandler _tokenHandler;

    private static string? _cachedSecret;
    private static DateTime _cacheExpiry;
    private static readonly TimeSpan CacheTtl = TimeSpan.FromMinutes(5);

    public JwtValidator(SecretsManagerService secretsManager)
    {
        _secretsManager = secretsManager;
        _tokenHandler = new JwtSecurityTokenHandler();
    }

    public async Task<JwtPayload?> ValidateAsync(string token)
    {
        try
        {
            var secret = await GetJwtSecretAsync();

            if (string.IsNullOrWhiteSpace(secret))
            {
                Console.WriteLine("JWT secret is null or empty");
                return null;
            }

            var validationParameters = new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)),
                ValidateIssuer = true,
                ValidIssuer = "AutoRepairShop",
                ValidateAudience = true,
                ValidAudience = "AutoRepairShopUsers",
                ValidateLifetime = true,
                ClockSkew = TimeSpan.FromMinutes(5)
            };

            var principal = _tokenHandler.ValidateToken(token, validationParameters, out var validatedToken);

            var payload = new JwtPayload
            {
                Sub = principal.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                      ?? principal.FindFirst("sub")?.Value,
                Email = principal.FindFirst(ClaimTypes.Email)?.Value 
                        ?? principal.FindFirst("email")?.Value,
                Role = principal.FindFirst(ClaimTypes.Role)?.Value 
                       ?? principal.FindFirst("role")?.Value,
                CustomerId = principal.FindFirst("customerId")?.Value
            };

            if (string.IsNullOrWhiteSpace(payload.Sub))
            {
                Console.WriteLine("JWT missing 'sub' claim");
                return null;
            }

            return payload;
        }
        catch (SecurityTokenExpiredException)
        {
            Console.WriteLine("JWT expired");
            return null;
        }
        catch (SecurityTokenInvalidSignatureException)
        {
            Console.WriteLine("JWT invalid signature");
            return null;
        }
        catch (SecurityTokenException ex)
        {
            Console.WriteLine($"JWT validation error: {ex.Message}");
            return null;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Unexpected error validating JWT: {ex.Message}");
            return null;
        }
    }

    private async Task<string?> GetJwtSecretAsync()
    {
        if (_cachedSecret != null && DateTime.UtcNow < _cacheExpiry)
        {
            return _cachedSecret;
        }

        var secret = await _secretsManager.GetSecretAsync("autorepair/jwt-secret");

        if (secret != null)
        {
            _cachedSecret = secret;
            _cacheExpiry = DateTime.UtcNow.Add(CacheTtl);
        }

        return secret;
    }
}
