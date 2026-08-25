# AutoRepairShop-Lambda
# AutoRepairShop Lambda Authorizer (.NET 8)

Lambda Authorizer desenvolvido em **C# .NET 8** para validação de tokens JWT.

## 🎯 Tecnologias

- **.NET 8** (C#)
- **AWS Lambda**
- **AWS Secrets Manager**
- **System.IdentityModel.Tokens.Jwt**
- **Terraform** (IaC)

## 🚀 Build e Deploy

### Pré-requisitos

- .NET 8 SDK
- AWS CLI configurado
- Amazon.Lambda.Tools (`dotnet tool install -g Amazon.Lambda.Tools`)

### Build Local

```bash
cd src/AutoRepairShop.Authorizer
dotnet build
dotnet test ../../tests/AutoRepairShop.Authorizer.Tests
