namespace AutoRepairShop.Login.Models;

public class Customer
{
    public int Id { get; set; }
    public string Cpf { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public bool IsActive { get; set; }
}
