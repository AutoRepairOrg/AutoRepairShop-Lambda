using AutoRepairShop.Authorizer.Models;

namespace AutoRepairShop.Authorizer.Services;

public interface IJwtValidator
{
    Task<JwtPayload?> ValidateAsync(string token);
}
