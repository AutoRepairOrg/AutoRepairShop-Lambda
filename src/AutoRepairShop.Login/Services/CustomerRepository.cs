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
                SELECT Id, Name, Document
                FROM Customers
                WHERE Document = @Cpf";
    
            using var command = new SqlCommand(query, connection);
            command.Parameters.AddWithValue("@Cpf", cpf);
    
            using var reader = await command.ExecuteReaderAsync();
    
            if (await reader.ReadAsync())
            {
                return new Customer
                {
                    Id = reader.GetGuid(0),
                    Name = reader.GetString(1),
                    Cpf = reader.GetString(2)
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
