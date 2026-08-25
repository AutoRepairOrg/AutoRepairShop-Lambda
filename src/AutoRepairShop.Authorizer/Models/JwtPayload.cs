namespace AutoRepairShop.Authorizer.Models;

public class JwtPayload
{
    public string? Sub { get; set; }
    public string? Email { get; set; }
    public string? Role { get; set; }
    public string? CustomerId { get; set; }
}
