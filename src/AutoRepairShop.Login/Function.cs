using Amazon.Lambda.Core;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using System.Text.Json;
using AutoRepairShop.Login.Models;
using AutoRepairShop.Login.Services;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace AutoRepairShop.Login;

public class Function
{
    private readonly ICpfValidator _cpfValidator;
    private static string? _cachedConnectionString;
    private static string? _cachedJwtSecret;

    public Function()
    {
        _cpfValidator = new CpfValidator();
    }

    public async Task<APIGatewayProxyResponse> FunctionHandler(
        APIGatewayProxyRequest request, 
        ILambdaContext context)
    {
        context.Logger.LogInformation("Login request received");

        try
        {
            var loginRequest = JsonSerializer.Deserialize<LoginRequest>(request.Body);

            if (loginRequest == null || string.IsNullOrWhiteSpace(loginRequest.Cpf))
            {
                return CreateResponse(400, new LoginResponse
                {
                    Success = false,
                    Message = "CPF é obrigatório"
                });
            }

            if (!_cpfValidator.IsValid(loginRequest.Cpf))
            {
                context.Logger.LogWarning($"CPF inválido: {loginRequest.Cpf}");
                return CreateResponse(400, new LoginResponse
                {
                    Success = false,
                    Message = "CPF inválido"
                });
            }

            var cpf = System.Text.RegularExpressions.Regex.Replace(loginRequest.Cpf, @"[^\d]", "");

            var connectionString = await GetConnectionStringAsync();
            var repository = new CustomerRepository(connectionString);
            var customer = await repository.GetByCpfAsync(cpf);

            if (customer == null)
            {
                context.Logger.LogWarning($"Cliente não encontrado: {cpf}");
                return CreateResponse(404, new LoginResponse
                {
                    Success = false,
                    Message = "Cliente não encontrado"
                });
            }

            if (!customer.IsActive)
            {
                context.Logger.LogWarning($"Cliente inativo: {cpf}");
                return CreateResponse(403, new LoginResponse
                {
                    Success = false,
                    Message = "Cliente inativo"
                });
            }

            var jwtSecret = await GetJwtSecretAsync();
            var jwtGenerator = new JwtGenerator(jwtSecret);
            var token = jwtGenerator.Generate(customer);

            context.Logger.LogInformation($"Token gerado com sucesso para cliente: {customer.Id}");

            return CreateResponse(200, new LoginResponse
            {
                Success = true,
                Token = token,
                Message = "Login realizado com sucesso"
            });
        }
        catch (Exception ex)
        {
            context.Logger.LogError($"Erro no login: {ex.Message}");
            context.Logger.LogError(ex.StackTrace);

            return CreateResponse(500, new LoginResponse
            {
                Success = false,
                Message = "Erro interno do servidor"
            });
        }
    }

    private async Task<string> GetConnectionStringAsync()
    {
        if (_cachedConnectionString != null)
            return _cachedConnectionString;

        var client = new AmazonSecretsManagerClient();
        var request = new GetSecretValueRequest
        {
            SecretId = Environment.GetEnvironmentVariable("DB_SECRET_NAME") ?? "autorepair/rds-credentials"
        };

        var response = await client.GetSecretValueAsync(request);
        var secret = JsonSerializer.Deserialize<Dictionary<string, string>>(response.SecretString);

        if (secret == null)
            throw new Exception("Secret do banco de dados está vazio");

        _cachedConnectionString = $"Server={secret["host"]},{secret["port"]};Database={secret["dbname"]};User Id={secret["username"]};Password={secret["password"]};TrustServerCertificate=True;";

        return _cachedConnectionString;
    }

    private async Task<string> GetJwtSecretAsync()
    {
        if (_cachedJwtSecret != null)
            return _cachedJwtSecret;

        var client = new AmazonSecretsManagerClient();
        var request = new GetSecretValueRequest
        {
            SecretId = Environment.GetEnvironmentVariable("JWT_SECRET_NAME") ?? "autorepair/jwt-secret"
        };

        var response = await client.GetSecretValueAsync(request);
        var secret = JsonSerializer.Deserialize<Dictionary<string, string>>(response.SecretString);

        if (secret == null || !secret.ContainsKey("key"))
            throw new Exception("Secret JWT está vazio ou sem chave 'key'");

        _cachedJwtSecret = secret["key"];
        return _cachedJwtSecret;
    }

    private APIGatewayProxyResponse CreateResponse(int statusCode, LoginResponse body)
    {
        return new APIGatewayProxyResponse
        {
            StatusCode = statusCode,
            Headers = new Dictionary<string, string>
            {
                { "Content-Type", "application/json" },
                { "Access-Control-Allow-Origin", "*" }
            },
            Body = JsonSerializer.Serialize(body)
        };
    }
}
