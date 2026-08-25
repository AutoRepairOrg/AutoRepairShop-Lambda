using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using AutoRepairShop.Login.Models;

namespace AutoRepairShop.Login.Services;

public interface IJwtGenerator
{
    string Generate(Customer customer);
}

public class JwtGenerator : IJwtGenerator
{
    private readonly string _secretKey;
    private readonly string _issuer;
    private readonly string _audience;
    private readonly int _expiresInMinutes;

    public JwtGenerator(string secretKey, string issuer = "AutoRepairShop", 
                        string audience = "AutoRepairShopUsers", int expiresInMinutes = 60)
    {
        _secretKey = secretKey;
        _issuer = issuer;
        _audience = audience;
        _expiresInMinutes = expiresInMinutes;
    }

    public string Generate(Customer customer)
    {
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, customer.Id.ToString()),
            new Claim(JwtRegisteredClaimNames.Email, customer.Email),
            new Claim("customerId", customer.Id.ToString()),
            new Claim("cpf", customer.Cpf),
            new Claim("name", customer.Name),
            new Claim(ClaimTypes.Role, "customer"),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_secretKey));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: _issuer,
            audience: _audience,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(_expiresInMinutes),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
