using AutoRepairShop.Authorizer.Models;

namespace AutoRepairShop.Authorizer.Services;

public interface IJwtValidator
{
    Task<AutoRepairShop.Authorizer.Models.JwtPayload?> ValidateAsync(string token);
}
