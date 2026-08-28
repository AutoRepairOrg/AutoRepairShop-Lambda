using Amazon.Lambda.Core;
using Amazon.Lambda.APIGatewayEvents;
using AutoRepairShop.Authorizer.Services;
using AutoRepairShop.Authorizer.Models;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace AutoRepairShop.Authorizer;

public class Function
{
    private readonly IJwtValidator _jwtValidator;

    public Function()
    {
        _jwtValidator = new JwtValidator(new SecretsManagerService());
    }

    public Function(IJwtValidator jwtValidator)
    {
        _jwtValidator = jwtValidator;
    }

    public async Task<APIGatewayCustomAuthorizerResponse> FunctionHandler(
        APIGatewayCustomAuthorizerRequest request,
        ILambdaContext context)
    {
        var logger = context.Logger;
        logger.LogInformation($"Authorizer invoked for method: {request.MethodArn}");

        try
        {
            var token = ExtractToken(request);

            if (string.IsNullOrWhiteSpace(token))
            {
                logger.LogWarning("No authorization token provided");
                return GenerateDenyPolicy("anonymous", request.MethodArn);
            }

            var payload = await _jwtValidator.ValidateAsync(token);

            if (payload == null)
            {
                logger.LogWarning("JWT validation failed");
                return GenerateDenyPolicy("user", request.MethodArn);
            }

            logger.LogInformation($"JWT validated successfully for user: {payload.Sub}");

            var contextOutput = new APIGatewayCustomAuthorizerContextOutput();
            contextOutput["userId"] = payload.Sub ?? string.Empty;
            contextOutput["email"] = payload.Email ?? string.Empty;
            contextOutput["role"] = payload.Role ?? "user";
            contextOutput["customerId"] = payload.CustomerId ?? string.Empty;

            return GenerateAllowPolicy(payload.Sub, request.MethodArn, contextOutput);
        }
        catch (Exception ex)
        {
            logger.LogError($"Authorizer error: {ex.Message}");
            logger.LogError(ex.StackTrace);
            return GenerateDenyPolicy("user", request.MethodArn);
        }
    }

    private string? ExtractToken(APIGatewayCustomAuthorizerRequest request)
    {
        var authHeader = request.Headers?.FirstOrDefault(h => 
            h.Key.Equals("Authorization", StringComparison.OrdinalIgnoreCase)).Value;

        if (string.IsNullOrWhiteSpace(authHeader))
            return null;

        const string bearerPrefix = "Bearer ";
        if (authHeader.StartsWith(bearerPrefix, StringComparison.OrdinalIgnoreCase))
        {
            return authHeader.Substring(bearerPrefix.Length).Trim();
        }

        return authHeader;
    }

    private APIGatewayCustomAuthorizerResponse GenerateAllowPolicy(
        string principalId, 
        string resource, 
        APIGatewayCustomAuthorizerContextOutput? context = null)
    {
        return GeneratePolicy(principalId, "Allow", resource, context);
    }

    private APIGatewayCustomAuthorizerResponse GenerateDenyPolicy(
        string principalId, 
        string resource)
    {
        return GeneratePolicy(principalId, "Deny", resource);
    }

    private APIGatewayCustomAuthorizerResponse GeneratePolicy(
        string principalId,
        string effect,
        string resource,
        APIGatewayCustomAuthorizerContextOutput? context = null)
    {
        var response = new APIGatewayCustomAuthorizerResponse
        {
            PrincipalID = principalId,
            PolicyDocument = new APIGatewayCustomAuthorizerPolicy
            {
                Version = "2012-10-17",
                Statement = new List<APIGatewayCustomAuthorizerPolicy.IAMPolicyStatement>
                {
                    new APIGatewayCustomAuthorizerPolicy.IAMPolicyStatement
                    {
                        Action = new HashSet<string> { "execute-api:Invoke" },
                        Effect = effect,
                        Resource = new HashSet<string> { resource }
                    }
                }
            }
        };

        if (context != null)
        {
            response.Context = context;
        }

        return response;
    }
}
