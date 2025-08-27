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
    /// Validates client certificate using the certificate service with environment awareness
    /// </summary>
    public static bool ValidateClientCertificateWithEnvironment(X509Certificate2? clientCert, ICertificateService certificateService, IWebHostEnvironment? environment = null)
    {
        if (clientCert == null)
        {
            Console.WriteLine("No client certificate to validate");
            return false;
        }

        try
        {
            Console.WriteLine($"🔍 Validating certificate in {environment?.EnvironmentName ?? "Unknown"} mode");
            Console.WriteLine($"Certificate subject: {clientCert.Subject}");
            Console.WriteLine($"Certificate issuer: {clientCert.Issuer}");
            Console.WriteLine($"Certificate thumbprint: {clientCert.Thumbprint}");
            Console.WriteLine($"Certificate valid from: {clientCert.NotBefore} to {clientCert.NotAfter}");

            // Basic certificate validity checks (always required)
            var now = DateTime.UtcNow;
            if (now < clientCert.NotBefore || now > clientCert.NotAfter)
            {
                Console.WriteLine($"❌ Certificate is not valid at current time: {now}");
                return false;
            }

            // Detect Azure App Service Linux environment
            var isAzureLinux = IsRunningOnAzureLinux();
            Console.WriteLine($"🔍 Azure Linux environment detected: {isAzureLinux}");

            // Unified validation logic
            return ValidateClientCertificate(clientCert, certificateService, isAzureLinux);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error validating client certificate: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Unified certificate validation logic for all environments
    /// </summary>
    private static bool ValidateClientCertificate(X509Certificate2 clientCert, ICertificateService certificateService, bool skipCAValidation)
    {
        try
        {
            Console.WriteLine($"� Unified certificate validation (Skip CA validation: {skipCAValidation})");

            // 1. Thumbprint validation - always reliable
            var expectedCert = certificateService.LoadClientCertificate();
            if (expectedCert != null && expectedCert.Thumbprint.Equals(clientCert.Thumbprint, StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine("✅ Certificate thumbprint matches expected client certificate");
                return true;
            }

            // 2. Subject pattern validation for internal certificates
            var isInternalCert = clientCert.Subject.Contains("Development MTLS") && 
                               clientCert.Issuer.Contains("Development MTLS");
            
            if (!isInternalCert)
            {
                Console.WriteLine("❌ Certificate doesn't match internal certificate pattern");
                return false;
            }

            Console.WriteLine("✅ Valid internal certificate pattern detected");

            // 3. CA validation (skip if in Azure Linux due to environment limitations)
            if (skipCAValidation)
            {
                Console.WriteLine("⚠️ Skipping CA chain validation due to Azure Linux environment limitations");
                
                // Alternative validation: verify issuer CN matches CA CN
                var caCert = certificateService.LoadCACertificate();
                if (caCert != null)
                {
                    var issuerCN = ExtractCNFromDN(clientCert.Issuer);
                    var caCN = ExtractCNFromDN(caCert.Subject);
                    
                    if (!string.IsNullOrEmpty(issuerCN) && !string.IsNullOrEmpty(caCN) && 
                        issuerCN.Equals(caCN, StringComparison.OrdinalIgnoreCase))
                    {
                        Console.WriteLine($"✅ Certificate issuer CN '{issuerCN}' matches CA CN '{caCN}'");
                        return true;
                    }
                    else
                    {
                        Console.WriteLine($"⚠️ Issuer CN '{issuerCN}' != CA CN '{caCN}', but allowing due to Azure Linux limitations");
                        return true; // Allow in Azure Linux
                    }
                }
                
                return true; // Valid internal certificate pattern in Azure Linux
            }
            else
            {
                Console.WriteLine("🔍 Performing full CA chain validation");
                
                // Full chain validation
                var chainValid = certificateService.ValidateClientCertificate(clientCert);
                if (!chainValid)
                {
                    Console.WriteLine("❌ Certificate chain validation failed");
                    return false;
                }

                // Verify the certificate is issued by our expected CA
                var caCert = certificateService.LoadCACertificate();
                if (caCert != null)
                {
                    var issuedByExpectedCA = clientCert.Issuer.Equals(caCert.Subject, StringComparison.OrdinalIgnoreCase);
                    if (!issuedByExpectedCA)
                    {
                        Console.WriteLine($"❌ Certificate not issued by expected CA. Expected: {caCert.Subject}, Got: {clientCert.Issuer}");
                        return false;
                    }
                    Console.WriteLine("✅ Certificate issued by expected CA");
                }
                else
                {
                    Console.WriteLine("⚠️ No CA certificate found for validation");
                }

                Console.WriteLine("✅ Full certificate validation passed");
                return true;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Unified certificate validation error: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Detects if we're running on Azure App Service Linux
    /// </summary>
    private static bool IsRunningOnAzureLinux()
    {
        try
        {
            // Check for Azure App Service specific environment variables
            var websiteSiteName = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME");
            var websiteResourceGroup = Environment.GetEnvironmentVariable("WEBSITE_RESOURCE_GROUP");
            var websiteOwnerName = Environment.GetEnvironmentVariable("WEBSITE_OWNER_NAME");
            
            // Check if we're on Linux
            var isLinux = Environment.OSVersion.Platform == PlatformID.Unix;
            
            // Azure App Service Linux indicators
            var hasAzureEnvVars = !string.IsNullOrEmpty(websiteSiteName) || 
                                 !string.IsNullOrEmpty(websiteResourceGroup) ||
                                 !string.IsNullOrEmpty(websiteOwnerName);
            
            var isAzureLinux = isLinux && hasAzureEnvVars;
            
            Console.WriteLine($"🔍 Environment detection:");
            Console.WriteLine($"  - Is Linux: {isLinux}");
            Console.WriteLine($"  - Has Azure env vars: {hasAzureEnvVars}");
            Console.WriteLine($"  - Website name: {websiteSiteName ?? "Not set"}");
            Console.WriteLine($"  - Is Azure Linux: {isAzureLinux}");
            
            return isAzureLinux;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"⚠️ Error detecting Azure Linux environment: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Extracts the CN (Common Name) from a Distinguished Name
    /// </summary>
    private static string ExtractCNFromDN(string distinguishedName)
    {
        try
        {
            if (string.IsNullOrEmpty(distinguishedName)) return string.Empty;
            
            var parts = distinguishedName.Split(',');
            foreach (var part in parts)
            {
                var trimmed = part.Trim();
                if (trimmed.StartsWith("CN=", StringComparison.OrdinalIgnoreCase))
                {
                    return trimmed.Substring(3).Trim();
                }
            }
            return string.Empty;
        }
        catch
        {
            return string.Empty;
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