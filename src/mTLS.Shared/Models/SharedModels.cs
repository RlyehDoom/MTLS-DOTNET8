using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography.X509Certificates;

namespace mTLS.Shared.Models;

public class CertificateInfo
{
    public string Subject { get; set; } = string.Empty;
    public string Issuer { get; set; } = string.Empty;
    public string SerialNumber { get; set; } = string.Empty;
    public string Thumbprint { get; set; } = string.Empty;
    public DateTime NotBefore { get; set; }
    public DateTime NotAfter { get; set; }
    public bool HasPrivateKey { get; set; }
    
    public static CertificateInfo FromX509Certificate(X509Certificate2 certificate)
    {
        return new CertificateInfo
        {
            Subject = certificate.Subject,
            Issuer = certificate.Issuer,
            SerialNumber = certificate.SerialNumber,
            Thumbprint = certificate.Thumbprint,
            NotBefore = certificate.NotBefore,
            NotAfter = certificate.NotAfter,
            HasPrivateKey = certificate.HasPrivateKey
        };
    }
}

public class mTLSTestResponse
{
    public string Message { get; set; } = string.Empty;
    public CertificateInfo? ClientCertificate { get; set; }
    public DateTime Timestamp { get; set; }
}

public class HealthResponse
{
    public string Status { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
}

public class WeatherForecast
{
    public DateOnly Date { get; set; }
    public int TemperatureC { get; set; }
    public string? Summary { get; set; }
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}

public class CertificateConfiguration
{
    public const string SectionName = "Certificates";
    
    [Required]
    public string ServerCert { get; set; } = string.Empty;
    
    [Required]
    public string ServerCertPassword { get; set; } = string.Empty;
    
    [Required]
    public string CACert { get; set; } = string.Empty;
    
    public string ClientCert { get; set; } = string.Empty;
    public string ClientCertPassword { get; set; } = string.Empty;
}

public class AzureCertificateConfiguration
{
    public const string SectionName = "AzureCertificates";
    
    public string ServerCertThumbprint { get; set; } = string.Empty;
    public string CACertThumbprint { get; set; } = string.Empty;
    public string ClientCertThumbprint { get; set; } = string.Empty;
}
