namespace AutoRepairShop.Login.Models;

using System.Text.Json.Serialization;

public class LoginRequest
{
    [JsonPropertyName("cpf")]
    public string Cpf { get; set; } = string.Empty;
}
