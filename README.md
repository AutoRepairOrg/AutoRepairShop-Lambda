
# 🔐 AutoRepairShop-Lambda

Funções Serverless (.NET 8) para autenticação e autorização do sistema AutoRepairShop.

## 📖 Sobre

Este repositório contém duas funções AWS Lambda em .NET 8:

1. **Login Lambda:** Autentica usuários via CPF e gera tokens JWT
2. **Authorizer Lambda:** Valida tokens JWT para proteger rotas da API

Ambas integradas com **AWS API Gateway** e **AWS Secrets Manager**.

---

## 🛠️ Tecnologias

- **.NET 8** (C#) - Runtime das Lambdas
- **AWS Lambda** - Serverless compute
- **AWS API Gateway** - Gerenciamento de APIs
- **AWS Secrets Manager** - Armazenamento seguro de chaves JWT
- **System.IdentityModel.Tokens.Jwt** - Geração e validação de JWT
- **Terraform** - Infraestrutura como código
- **GitHub Actions** - CI/CD automático

---

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│                    Cliente (Mobile/Web)                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ HTTPS Request
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                   API Gateway (REST)                         │
│  https://xxxxx.execute-api.us-east-1.amazonaws.com/prod     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  POST /auth/login                                            │
│      │                                                       │
│      ├──────────────────────┐                                │
│      ▼                      │                                │
│  ┌─────────────────────┐   │                                │
│  │  Lambda Login       │   │                                │
│  │  (.NET 8)           │   │                                │
│  │                     │   │                                │
│  │  1. Valida CPF      │   │                                │
│  │  2. Consulta RDS    │───┼──► RDS SQL Server              │
│  │  3. Gera JWT        │   │    (Customer/Admin)            │
│  │  4. Retorna Token   │   │                                │
│  └─────────────────────┘   │                                │
│           │                 │                                │
│           │                 │                                │
│  GET /api/* (rotas protegidas)                               │
│      │                      │                                │
│      ▼                      │                                │
│  ┌─────────────────────┐   │                                │
│  │ Lambda Authorizer   │   │                                │
│  │ (.NET 8)            │   │                                │
│  │                     │   │                                │
│  │  1. Extrai Token    │   │                                │
│  │  2. Valida JWT      │◄──┼─── AWS Secrets Manager         │
│  │  3. Retorna Policy  │   │    (JWT Secret Key)            │
│  └─────────────────────┘   │                                │
│           │                 │                                │
│           │ Allow/Deny      │                                │
│           ▼                 │                                │
│      Backend API ───────────┘                                │
│      (Kubernetes)                                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚡ Funções Lambda

### **1. Login Lambda**

**Responsabilidades:**
- ✅ Validar formato do CPF
- ✅ Consultar existência do cliente no banco RDS
- ✅ Verificar status do cliente (ativo/inativo)
- ✅ Gerar token JWT válido
- ✅ Retornar token + informações do usuário

**Endpoint:**
```
POST /auth/login
Content-Type: application/json

{
  "cpf": "12345678901"
}
```

**Resposta de Sucesso:**
```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "message": "Login realizado com sucesso",
  "user": {
    "id": "uuid",
    "name": "Cliente Exemplo",
    "email": "cliente@example.com"
  }
}
```

**Resposta de Erro:**
```json
{
  "success": false,
  "token": null,
  "message": "CPF não encontrado ou inválido"
}
```

---

### **2. Authorizer Lambda**

**Responsabilidades:**
- ✅ Extrair token do header `Authorization: Bearer <token>`
- ✅ Validar assinatura do JWT
- ✅ Verificar expiração do token
- ✅ Retornar IAM Policy (Allow/Deny)
- ✅ Injetar contexto do usuário nas rotas protegidas

**Fluxo:**
```
1. Cliente envia request com header:
   Authorization: Bearer eyJhbGc...

2. API Gateway invoca Authorizer Lambda

3. Lambda valida o token:
   - Válido → Retorna Policy "Allow"
   - Inválido → Retorna Policy "Deny"

4. API Gateway roteia (ou bloqueia) a request
```

**IAM Policy Response:**
```json
{
  "principalId": "user-id-123",
  "policyDocument": {
    "Version": "2012-10-17",
    "Statement": [{
      "Action": "execute-api:Invoke",
      "Effect": "Allow",
      "Resource": "arn:aws:execute-api:*:*:*"
    }]
  },
  "context": {
    "userId": "uuid",
    "email": "user@example.com",
    "role": "Customer"
  }
}
```

---

## ✅ Pré-requisitos

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [AWS CLI](https://aws.amazon.com/cli/) configurado
- [Terraform](https://www.terraform.io/downloads) >= 1.6
- [Amazon.Lambda.Tools](https://github.com/aws/aws-extensions-for-dotnet-cli)
  ```bash
  dotnet tool install -g Amazon.Lambda.Tools
  ```

---

## 🚀 Instalação e Deploy

### **Método 1: Via CI/CD (Recomendado)**

1. **Configure os secrets no GitHub:**
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_SESSION_TOKEN`

2. **Faça um commit:**
   ```bash
   git add src/
   git commit -m "feat: atualizar lógica de autenticação"
   git push origin master
   ```

3. **O workflow CD irá:**
   - ✅ Build das funções .NET 8
   - ✅ Criar pacotes .zip
   - ✅ Provisionar Lambdas via Terraform
   - ✅ Deploy automático
   - ✅ Configurar API Gateway

---

### **Método 2: Deploy Manual**

```bash
# 1. Clone o repositório
git clone https://github.com/AutoRepairOrg/AutoRepairShop-Lambda.git
cd AutoRepairShop-Lambda

# 2. Build Login Lambda
cd src/AutoRepairShop.Login
dotnet restore
dotnet publish -c Release -o publish
cd publish && zip -r ../../../login-lambda.zip .

# 3. Build Authorizer Lambda
cd ../../AutoRepairShop.Authorizer
dotnet restore
dotnet publish -c Release -o publish
cd publish && zip -r ../../../authorizer-lambda.zip .

# 4. Deploy com Terraform
cd ../../terraform
terraform init
terraform plan
terraform apply

# 5. Ou deploy direto via AWS CLI
aws lambda update-function-code \
  --function-name autorepair-login \
  --zip-file fileb://login-lambda.zip

aws lambda update-function-code \
  --function-name autorepair-authorizer \
  --zip-file fileb://authorizer-lambda.zip
```

---

## 🔄 CI/CD

### **Workflows**

#### **CI - Validação (Pull Requests)**
```yaml
Trigger: Pull Request → master
Jobs:
  build-and-test:
    - Setup .NET 8
    - Restore dependencies
    - Build Login Lambda
    - Build Authorizer Lambda
    - Run tests (se existirem)
  
  terraform-validate:
    - Terraform Format Check
    - Terraform Init
    - Terraform Validate
```

#### **CD - Deploy (Push to master)**
```yaml
Trigger: Push → master
Jobs:
  build-and-deploy:
    - Build .NET Lambdas
    - Package .zip files
    - Terraform Apply (criar/atualizar recursos)
    - Deploy Lambda code
    - Test API Gateway endpoint
```

### **Branch Protection**

- ✅ Pull Requests obrigatórios
- ✅ CI deve passar antes do merge
- ✅ Deploy automático após merge

---

## 📁 Estrutura do Projeto

```
AutoRepairShop-Lambda/
├── .github/
│   └── workflows/
│       ├── ci.yml                # Validação em PRs
│       └── deploy-lambda.yml     # Deploy em master
├── src/
│   ├── AutoRepairShop.Login/
│   │   ├── Function.cs           # Handler do Lambda
│   │   ├── Models/
│   │   │   ├── LoginRequest.cs
│   │   │   ├── LoginResponse.cs
│   │   │   └── Customer.cs
│   │   ├── Services/
│   │   │   ├── JwtGenerator.cs
│   │   │   ├── CpfValidator.cs
│   │   │   └── CustomerRepository.cs
│   │   └── AutoRepairShop.Login.csproj
│   │
│   └── AutoRepairShop.Authorizer/
│       ├── Function.cs           # Handler do Lambda
│       ├── Models/
│       │   └── JwtPayload.cs
│       ├── Services/
│       │   ├── IJwtValidator.cs
│       │   ├── JwtValidator.cs
│       │   └── SecretsManagerService.cs
│       └── AutoRepairShop.Authorizer.csproj
│
├── terraform/
│   ├── main.tf                   # Lambdas + API Gateway
│   ├── outputs.tf
│   ├── variables.tf
│   └── .gitignore
│
├── tests/                        # (Futuro)
└── README.md                     # Este arquivo
```

---

## 🔌 API Gateway Integration

### **Recursos Criados pelo Terraform**

```hcl
# API Gateway REST
resource "aws_api_gateway_rest_api" "autorepair_api"

# Rota: POST /auth/login
resource "aws_api_gateway_resource" "login"
resource "aws_api_gateway_method" "login_post"
resource "aws_api_gateway_integration" "login_lambda"

# Lambda Authorizer
resource "aws_api_gateway_authorizer" "jwt_authorizer"

# Stage: prod
resource "aws_api_gateway_stage" "prod"
```

### **Endpoints**

```
Base URL: https://<API_ID>.execute-api.us-east-1.amazonaws.com/prod

POST /auth/login          → Lambda Login (público)
GET  /api/*               → Backend API (protegido por Authorizer)
```

---

## 🔐 Autenticação JWT

### **Geração de Token (Login Lambda)**

```csharp
var tokenHandler = new JwtSecurityTokenHandler();
var key = Encoding.UTF8.GetBytes(jwtSecret);

var tokenDescriptor = new SecurityTokenDescriptor
{
    Subject = new ClaimsIdentity(new[]
    {
        new Claim(ClaimTypes.NameIdentifier, customer.Id),
        new Claim(ClaimTypes.Email, customer.Email),
        new Claim("customerId", customer.Id)
    }),
    Expires = DateTime.UtcNow.AddHours(24),
    Issuer = "AutoRepairShop",
    Audience = "AutoRepairShopUsers",
    SigningCredentials = new SigningCredentials(
        new SymmetricSecurityKey(key),
        SecurityAlgorithms.HmacSha256Signature
    )
};

var token = tokenHandler.CreateToken(tokenDescriptor);
return tokenHandler.WriteToken(token);
```

### **Validação de Token (Authorizer Lambda)**

```csharp
var tokenHandler = new JwtSecurityTokenHandler();
var key = Encoding.UTF8.GetBytes(jwtSecret);

var validationParameters = new TokenValidationParameters
{
    ValidateIssuerSigningKey = true,
    IssuerSigningKey = new SymmetricSecurityKey(key),
    ValidateIssuer = true,
    ValidIssuer = "AutoRepairShop",
    ValidateAudience = true,
    ValidAudience = "AutoRepairShopUsers",
    ValidateLifetime = true,
    ClockSkew = TimeSpan.Zero
};

var principal = tokenHandler.ValidateToken(token, validationParameters, out _);
```

### **Chave JWT no Secrets Manager**

```bash
# Criar secret
aws secretsmanager create-secret \
  --name autorepair/jwt-secret \
  --secret-string '{"key":"MinhaChaveSuperSecretaComMaisDe256Bits"}'

# Recuperar secret (usado pelas Lambdas)
aws secretsmanager get-secret-value \
  --secret-id autorepair/jwt-secret \
  --query SecretString --output text
```

---

## 🧪 Testes

### **Teste Manual - Login**

```bash
# Variável com a URL do API Gateway
API_URL="https://<API_ID>.execute-api.us-east-1.amazonaws.com/prod"

# Teste 1: Login com sucesso
curl -X POST $API_URL/auth/login \
  -H "Content-Type: application/json" \
  -d '{"cpf":"12345678901"}' \
  | jq

# Teste 2: CPF inválido
curl -X POST $API_URL/auth/login \
  -H "Content-Type: application/json" \
  -d '{"cpf":"00000000000"}' \
  | jq

# Teste 3: Cliente não encontrado
curl -X POST $API_URL/auth/login \
  -H "Content-Type: application/json" \
  -d '{"cpf":"99999999999"}' \
  | jq
```

### **Teste Manual - Authorizer**

```bash
# 1. Fazer login e pegar token
TOKEN=$(curl -s -X POST $API_URL/auth/login \
  -H "Content-Type: application/json" \
  -d '{"cpf":"12345678901"}' \
  | jq -r '.token')

echo "Token: $TOKEN"

# 2. Testar rota protegida
curl -X GET $API_URL/api/customers \
  -H "Authorization: Bearer $TOKEN" \
  | jq
```

### **Testes Unitários (Futuro)**

```bash
# Adicionar projeto de testes
dotnet new xunit -n AutoRepairShop.Lambda.Tests

# Executar testes
dotnet test
```

---

## 📈 Monitoramento

### **CloudWatch Logs**

```bash
# Ver logs do Login Lambda
aws logs tail /aws/lambda/autorepair-login --follow

# Ver logs do Authorizer Lambda
aws logs tail /aws/lambda/autorepair-authorizer --follow

# Filtrar erros
aws logs filter-log-events \
  --log-group-name /aws/lambda/autorepair-login \
  --filter-pattern "ERROR"
```

### **CloudWatch Metrics**

```bash
# Invocações
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=autorepair-login \
  --start-time 2026-08-28T00:00:00Z \
  --end-time 2026-08-28T23:59:59Z \
  --period 3600 \
  --statistics Sum

# Erros
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=autorepair-login \
  --start-time 2026-08-28T00:00:00Z \
  --end-time 2026-08-28T23:59:59Z \
  --period 3600 \
  --statistics Sum

# Duração
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=autorepair-login \
  --start-time 2026-08-28T00:00:00Z \
  --end-time 2026-08-28T23:59:59Z \
  --period 3600 \
  --statistics Average
```

---

## 🔧 Troubleshooting

### **Lambda retorna 502 Bad Gateway**

```bash
# Verificar logs
aws logs tail /aws/lambda/autorepair-login --since 5m

# Causas comuns:
# - Exceção não tratada no código
# - Timeout (aumentar para 30s)
# - Problema de conexão com RDS
```

### **Token JWT inválido**

```bash
# Verificar secret no Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id autorepair/jwt-secret

# Causas comuns:
# - Chave JWT diferente entre Login e Authorizer
# - Token expirado (verificar claims)
# - Formato do token incorreto
```

### **CPF não encontrado**

```bash
# Verificar conexão com RDS
aws rds describe-db-instances \
  --db-instance-identifier autorepair-sqlserver

# Testar query no banco
# (via SQL client)
SELECT * FROM Customers WHERE Document = '12345678901';
```

---

## 📄 Licença

Este projeto faz parte do **Tech Challenge - Fase 3** da FIAP.

**Autores:**
- Dhiulia da Silva
- Mateus Pinheiro

---

## 🔗 Links Relacionados

- [AutoRepairShop-Api](https://github.com/AutoRepairOrg/AutoRepairShop-Api) - Aplicação principal
- [AutoRepairShop-Kubernetes](https://github.com/AutoRepairOrg/AutoRepairShop-Kubernetes) - Infraestrutura K8s
- [AutoRepairShop-Database](https://github.com/AutoRepairOrg/AutoRepairShop-Database) - RDS SQL Server
