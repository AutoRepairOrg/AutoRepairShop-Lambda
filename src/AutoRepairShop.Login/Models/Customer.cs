namespace AutoRepairShop.Login.Models;

public class Customer
{
       public Guid Id { get; private set; }
    public string Name { get; private set; } = string.Empty;
    public Document Document { get; private set; } = null!;
    public string Phone { get; private set; } = string.Empty;
    public string Email { get; private set; } = string.Empty;
    public string Username { get; private set; } = string.Empty;
    public string Password { get; private set; } = string.Empty;
}
