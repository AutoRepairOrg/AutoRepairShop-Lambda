using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using System.Text.Json;

namespace AutoRepairShop.Authorizer.Services;

public class SecretsManagerService
{
    private readonly IAmazonSecretsManager _client;

    public SecretsManagerService()
    {
        _client = new AmazonSecretsManagerClient();
    }

    public async Task<string?> GetSecretAsync(string secretName)
    {
        try
        {
            Console.WriteLine($"Fetching secret: {secretName}");

            var request = new GetSecretValueRequest
            {
                SecretId = secretName
            };

            var response = await _client.GetSecretValueAsync(request);

            var secretJson = JsonSerializer.Deserialize<Dictionary<string, string>>(response.SecretString);

            if (secretJson != null && secretJson.TryGetValue("key", out var key))
            {
                Console.WriteLine("Secret fetched successfully");
                return key;
            }

            Console.WriteLine("Secret JSON missing 'key' field");
            return null;
        }
        catch (ResourceNotFoundException)
        {
            Console.WriteLine($"Secret not found: {secretName}");
            return null;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error fetching secret: {ex.Message}");
            return null;
        }
    }
}
