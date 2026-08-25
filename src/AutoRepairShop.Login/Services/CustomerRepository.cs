using System.Data.SqlClient;
using AutoRepairShop.Login.Models;

namespace AutoRepairShop.Login.Services;

public interface ICustomerRepository
{
    Task<Customer?> GetByCpfAsync(string cpf);
}

public class CustomerRepository : ICustomerRepository
{
    private readonly string _connectionString;

    public CustomerRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<Customer?> GetByCpfAsync(string cpf)
    {
        try
        {
            using var connection = new SqlConnection(_connectionString);
            await connection.OpenAsync();

            var query = @"
                SELECT Id, Cpf, Name, Email, IsActive 
                FROM Customers 
                WHERE Cpf = @Cpf";

            using var command = new SqlCommand(query, connection);
            command.Parameters.AddWithValue("@Cpf", cpf);

            using var reader = await command.ExecuteReaderAsync();

            if (await reader.ReadAsync())
            {
                return new Customer
                {
                    Id = reader.GetInt32(0),
                    Cpf = reader.GetString(1),
                    Name = reader.GetString(2),
                    Email = reader.GetString(3),
                    IsActive = reader.GetBoolean(4)
                };
            }

            return null;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Erro ao consultar cliente: {ex.Message}");
            throw;
        }
    }
}
