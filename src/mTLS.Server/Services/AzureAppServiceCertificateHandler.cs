using System.Security.Cryptography.X509Certificates;
using System.Text;
using mTLS.Shared.Services;

namespace mTLS.Server.Services;

public static class AzureAppServiceCertificateHandler
{
    /// <summary>
    /// Extracts client certificate from Azure App Service X-ARR-ClientCert header
    /// </summary>
    public static X509Certificate2? GetClientCertificateFromHeader(HttpContext context)
    {
        try
        {
            // Azure App Service forwards client certificates in this header
            var clientCertHeader = context.Request.Headers["X-ARR-ClientCert"].FirstOrDefault();
            
            if (string.IsNullOrEmpty(clientCertHeader))
            {
                Console.WriteLine("No X-ARR-ClientCert header found");
                return null;
            }

            Console.WriteLine($"Found X-ARR-ClientCert header (length: {clientCertHeader.Length})");

            // The certificate is base64 encoded
            var certBytes = Convert.FromBase64String(clientCertHeader);
            var certificate = new X509Certificate2(certBytes);
            
            Console.WriteLine($"Successfully parsed client certificate: {certificate.Subject}");
            return certificate;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error parsing client certificate from header: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Validates client certificate using the certificate service
    /// </summary>
    public static bool ValidateClientCertificate(X509Certificate2? clientCert, ICertificateService certificateService)
    {
        if (clientCert == null)
        {
            Console.WriteLine("No client certificate to validate");
            return false;
        }

        try
        {
            var isValid = certificateService.ValidateClientCertificate(clientCert);
            Console.WriteLine($"Certificate validation result: {isValid}");
            Console.WriteLine($"Certificate subject: {clientCert.Subject}");
            Console.WriteLine($"Certificate issuer: {clientCert.Issuer}");
            Console.WriteLine($"Certificate thumbprint: {clientCert.Thumbprint}");
            
            return isValid;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error validating client certificate: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Checks if request is coming from Azure App Service by validating headers
    /// This is a basic security check - in production you'd want more robust validation
    /// </summary>
    public static bool IsFromAzureAppService(HttpContext context)
    {
        // Azure App Service adds these headers
        var hasAzureHeaders = context.Request.Headers.ContainsKey("X-ARR-SSL") ||
                             context.Request.Headers.ContainsKey("X-Forwarded-For") ||
                             context.Request.Headers.ContainsKey("X-Forwarded-Proto");

        // Additional check: verify X-Forwarded-Proto is https
        var forwardedProto = context.Request.Headers["X-Forwarded-Proto"].FirstOrDefault();
        var isHttps = string.Equals(forwardedProto, "https", StringComparison.OrdinalIgnoreCase);

        Console.WriteLine($"Azure headers present: {hasAzureHeaders}, HTTPS forwarded: {isHttps}");
        
        return hasAzureHeaders && isHttps;
    }
}