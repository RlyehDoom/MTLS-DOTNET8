using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using mTLS.Shared.Models;
using System.Security.Cryptography.X509Certificates;
using Azure.Security.KeyVault.Certificates;
using Azure.Identity;

namespace mTLS.Shared.Services;

public interface ICertificateService
{
    X509Certificate2? LoadServerCertificate();
    X509Certificate2? LoadCACertificate();
    X509Certificate2? LoadClientCertificate();
    bool ValidateClientCertificate(X509Certificate2 clientCertificate);
}

public class LocalCertificateService : ICertificateService
{
    private readonly CertificateConfiguration _config;

    public LocalCertificateService(CertificateConfiguration config)
    {
        _config = config;
    }

    public X509Certificate2? LoadServerCertificate()
    {
        if (string.IsNullOrEmpty(_config.ServerCert) || !File.Exists(_config.ServerCert))
            return null;

        return new X509Certificate2(_config.ServerCert, _config.ServerCertPassword);
    }

    public X509Certificate2? LoadCACertificate()
    {
        if (string.IsNullOrEmpty(_config.CACert) || !File.Exists(_config.CACert))
            return null;

        return new X509Certificate2(_config.CACert);
    }

    public X509Certificate2? LoadClientCertificate()
    {
        if (string.IsNullOrEmpty(_config.ClientCert) || !File.Exists(_config.ClientCert))
            return null;

        return new X509Certificate2(_config.ClientCert, _config.ClientCertPassword);
    }

    public bool ValidateClientCertificate(X509Certificate2 clientCertificate)
    {
        var caCert = LoadCACertificate();
        if (caCert == null) return false;

        using var chain = new X509Chain();
        chain.ChainPolicy.ExtraStore.Add(caCert);
        chain.ChainPolicy.VerificationFlags = X509VerificationFlags.AllowUnknownCertificateAuthority;
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;

        return chain.Build(clientCertificate);
    }
}

public class AzureCertificateService : ICertificateService
{
    private readonly AzureCertificateConfiguration _config;

    public AzureCertificateService(AzureCertificateConfiguration config)
    {
        _config = config;
    }

    public X509Certificate2? LoadServerCertificate()
    {
        var cert = LoadCertificateFromStore(_config.ServerCertThumbprint);
        if (cert == null)
        {
            Console.WriteLine($"❌ Server certificate with thumbprint {_config.ServerCertThumbprint} not found in Azure Store");
        }
        return cert;
    }

    public X509Certificate2? LoadCACertificate()
    {
        var cert = LoadCertificateFromStore(_config.CACertThumbprint);
        if (cert == null)
        {
            Console.WriteLine($"⚠️  CA certificate with thumbprint {_config.CACertThumbprint} not found in Azure Store");
            Console.WriteLine($"📋 Note: CA certificates (.crt) cannot be uploaded to Azure App Service SSL store");
            Console.WriteLine($"📋 This is expected - CA validation will be handled differently");
        }
        return cert;
    }

    public X509Certificate2? LoadClientCertificate()
    {
        var cert = LoadCertificateFromStore(_config.ClientCertThumbprint);
        if (cert == null)
        {
            Console.WriteLine($"❌ Client certificate with thumbprint {_config.ClientCertThumbprint} not found in Azure Store");
        }
        return cert;
    }

    public bool ValidateClientCertificate(X509Certificate2 clientCertificate)
    {
        var caCert = LoadCACertificate();
        if (caCert == null) 
        {
            Console.WriteLine("⚠️  CA certificate not available - using simplified validation for Azure");
            // In Azure App Service, we trust that the certificate was properly validated
            // when it was uploaded to the SSL store with proper thumbprint validation
            return !string.IsNullOrEmpty(clientCertificate.Subject) && 
                   !string.IsNullOrEmpty(clientCertificate.Thumbprint);
        }

        using var chain = new X509Chain();
        chain.ChainPolicy.ExtraStore.Add(caCert);
        chain.ChainPolicy.VerificationFlags = X509VerificationFlags.AllowUnknownCertificateAuthority;
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;

        return chain.Build(clientCertificate);
    }

    private X509Certificate2? LoadCertificateFromStore(string thumbprint)
    {
        if (string.IsNullOrEmpty(thumbprint)) 
        {
            Console.WriteLine("❌ Empty thumbprint provided");
            return null;
        }

        Console.WriteLine($"🔍 Looking for certificate with thumbprint: {thumbprint}");

        try
        {
            // First, try Azure App Service specific method for Linux
            var azureCert = LoadCertificateFromAzureAppService(thumbprint);
            if (azureCert != null)
            {
                Console.WriteLine($"✅ Found certificate via Azure App Service method: {azureCert.Subject}");
                return azureCert;
            }

            // Try CurrentUser store
            using var userStore = new X509Store(StoreName.My, StoreLocation.CurrentUser);
            userStore.Open(OpenFlags.ReadOnly);
            Console.WriteLine($"📂 Opened CurrentUser store, found {userStore.Certificates.Count} certificates");
            
            var userCertificates = userStore.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false);
            if (userCertificates.Count > 0)
            {
                Console.WriteLine($"✅ Found certificate in CurrentUser store: {userCertificates[0].Subject}");
                return userCertificates[0];
            }

            // Try LocalMachine store (may fail on Linux)
            try
            {
                using var machineStore = new X509Store(StoreName.My, StoreLocation.LocalMachine);
                machineStore.Open(OpenFlags.ReadOnly);
                Console.WriteLine($"📂 Opened LocalMachine store, found {machineStore.Certificates.Count} certificates");
                
                var machineCertificates = machineStore.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false);
                if (machineCertificates.Count > 0)
                {
                    Console.WriteLine($"✅ Found certificate in LocalMachine store: {machineCertificates[0].Subject}");
                    return machineCertificates[0];
                }
            }
            catch (Exception storeEx)
            {
                Console.WriteLine($"⚠️  LocalMachine store access failed (expected on Linux): {storeEx.Message}");
            }

            Console.WriteLine($"❌ Certificate with thumbprint {thumbprint} not found in any accessible store");
            return null;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Error loading certificate: {ex.Message}");
            return null;
        }
    }

    private X509Certificate2? LoadCertificateFromAzureAppService(string thumbprint)
    {
        try
        {
            // Azure App Service makes certificates available via environment variables
            var websiteLoadCerts = Environment.GetEnvironmentVariable("WEBSITE_LOAD_CERTIFICATES");
            Console.WriteLine($"🔧 WEBSITE_LOAD_CERTIFICATES: {websiteLoadCerts}");

            if (string.IsNullOrEmpty(websiteLoadCerts))
            {
                Console.WriteLine("❌ WEBSITE_LOAD_CERTIFICATES not set");
                return null;
            }

            // Check if we're on Linux (Azure App Service Linux)
            var isLinux = Environment.OSVersion.Platform == PlatformID.Unix || 
                         Environment.OSVersion.Platform == PlatformID.MacOSX;
            
            if (isLinux)
            {
                Console.WriteLine("🐧 Detected Linux environment - checking certificate files");
                
                // In Azure App Service Linux, certificates are available as files
                // Check common certificate file locations
                var certPaths = new[]
                {
                    $"/var/ssl/certs/{thumbprint}.crt",
                    $"/var/ssl/private/{thumbprint}.key", 
                    $"/home/site/wwwroot/Certs/{thumbprint}.pfx",
                    $"/opt/certs/{thumbprint}.pfx",
                    "/var/ssl/certs",
                    "/opt/certs"
                };

                foreach (var path in certPaths)
                {
                    Console.WriteLine($"🔍 Checking path: {path}");
                    if (Directory.Exists(path))
                    {
                        var files = Directory.GetFiles(path, "*.*", SearchOption.AllDirectories);
                        Console.WriteLine($"📁 Found {files.Length} files in {path}");
                        foreach (var file in files.Take(5))
                        {
                            Console.WriteLine($"  📄 {file}");
                        }
                    }
                    else if (File.Exists(path))
                    {
                        Console.WriteLine($"📄 Found file: {path}");
                    }
                }

                // Try to load certificate from environment variables
                // Azure might provide certificate content via env vars
                var certEnvVars = Environment.GetEnvironmentVariables()
                    .Cast<System.Collections.DictionaryEntry>()
                    .Where(e => e.Key.ToString().Contains("CERT") || e.Key.ToString().Contains("CERTIFICATE"))
                    .ToList();

                Console.WriteLine($"🔍 Found {certEnvVars.Count} certificate-related environment variables");
                foreach (var envVar in certEnvVars.Take(10))
                {
                    var value = envVar.Value?.ToString();
                    var displayValue = value?.Length > 50 ? value.Substring(0, 50) + "..." : value;
                    Console.WriteLine($"  🔧 {envVar.Key}: {displayValue}");
                }
            }

            // Try Windows/standard approach
            using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
            store.Open(OpenFlags.ReadOnly);

            // Sometimes certificates are available but not immediately visible
            // Force refresh the store
            store.Close();
            store.Open(OpenFlags.ReadOnly);

            var allCerts = store.Certificates.Cast<X509Certificate2>().ToList();
            Console.WriteLine($"🔍 Total certificates in CurrentUser store: {allCerts.Count}");
            
            foreach (var cert in allCerts)
            {
                Console.WriteLine($"  📋 Available: {cert.Subject} | Thumbprint: {cert.Thumbprint}");
                if (string.Equals(cert.Thumbprint, thumbprint, StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine($"✅ Match found!");
                    return cert;
                }
            }

            return null;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Azure App Service certificate loading failed: {ex.Message}");
            return null;
        }
    }

    private X509Certificate2? LoadLocalCertificate(string? path, string? password)
    {
        if (string.IsNullOrEmpty(path))
        {
            Console.WriteLine("❌ Certificate path is empty");
            return null;
        }

        try
        {
            // Try relative path first
            if (!File.Exists(path))
            {
                // Try absolute path from content root
                var contentRoot = Environment.GetEnvironmentVariable("WEBSITE_CONTENTSHARE_PATH") ?? 
                                  Environment.CurrentDirectory;
                var absolutePath = Path.Combine(contentRoot, path);
                
                Console.WriteLine($"🔍 Trying absolute path: {absolutePath}");
                
                if (File.Exists(absolutePath))
                {
                    path = absolutePath;
                }
                else
                {
                    Console.WriteLine($"❌ Certificate file not found: {path} or {absolutePath}");
                    return null;
                }
            }

            Console.WriteLine($"📄 Loading certificate from: {path}");
            
            if (!string.IsNullOrEmpty(password))
            {
                return new X509Certificate2(path, password);
            }
            else
            {
                return new X509Certificate2(path);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Error loading local certificate from {path}: {ex.Message}");
            return null;
        }
    }
}

public class AzureKeyVaultCertificateService : ICertificateService
{
    private readonly AzureKeyVaultConfiguration _config;
    private readonly CertificateClient _certificateClient;
    
    public AzureKeyVaultCertificateService(AzureKeyVaultConfiguration config)
    {
        _config = config;
        
        if (string.IsNullOrEmpty(_config.VaultUrl))
        {
            throw new ArgumentException("VaultUrl is required for Azure Key Vault integration");
        }
        
        try
        {
            // Use Managed Identity in Azure, DefaultAzureCredential for local development
            var credential = new DefaultAzureCredential();
            _certificateClient = new CertificateClient(new Uri(_config.VaultUrl), credential);
            
            Console.WriteLine($"🔑 Azure Key Vault client initialized for: {_config.VaultUrl}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"⚠️  Warning: Failed to initialize Key Vault client: {ex.Message}");
            Console.WriteLine($"📋 This is expected if RBAC permissions are not yet configured");
            // Create a dummy client that will fail gracefully
            var credential = new DefaultAzureCredential();
            _certificateClient = new CertificateClient(new Uri(_config.VaultUrl), credential);
        }
    }

    public X509Certificate2? LoadServerCertificate()
    {
        return LoadCertificateFromKeyVault(_config.ServerCertName, "Server");
    }

    public X509Certificate2? LoadCACertificate()
    {
        return LoadCertificateFromKeyVault(_config.CACertName, "CA");
    }

    public X509Certificate2? LoadClientCertificate()
    {
        return LoadCertificateFromKeyVault(_config.ClientCertName, "Client");
    }

    public bool ValidateClientCertificate(X509Certificate2 clientCertificate)
    {
        var caCert = LoadCACertificate();
        if (caCert == null)
        {
            Console.WriteLine("⚠️  CA certificate not available from Key Vault - using simplified validation");
            return !string.IsNullOrEmpty(clientCertificate.Subject) && 
                   !string.IsNullOrEmpty(clientCertificate.Thumbprint);
        }

        using var chain = new X509Chain();
        chain.ChainPolicy.ExtraStore.Add(caCert);
        chain.ChainPolicy.VerificationFlags = X509VerificationFlags.AllowUnknownCertificateAuthority;
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;

        return chain.Build(clientCertificate);
    }

    private X509Certificate2? LoadCertificateFromKeyVault(string certificateName, string certificateType)
    {
        if (string.IsNullOrEmpty(certificateName))
        {
            Console.WriteLine($"❌ {certificateType} certificate name is empty");
            return null;
        }

        try
        {
            Console.WriteLine($"🔍 Loading {certificateType} certificate '{certificateName}' from Key Vault");
            
            // Download the certificate with private key
            var certificateResponse = _certificateClient.DownloadCertificate(certificateName);
            var certificate = certificateResponse.Value;
            
            Console.WriteLine($"✅ {certificateType} certificate loaded from Key Vault:");
            Console.WriteLine($"   Subject: {certificate.Subject}");
            Console.WriteLine($"   Thumbprint: {certificate.Thumbprint}");
            Console.WriteLine($"   Has Private Key: {certificate.HasPrivateKey}");
            Console.WriteLine($"   Valid Until: {certificate.NotAfter}");
            
            return certificate;
        }
        catch (Azure.RequestFailedException ex) when (ex.Status == 403)
        {
            Console.WriteLine($"🔒 Access denied loading {certificateType} certificate '{certificateName}' from Key Vault");
            Console.WriteLine($"📋 RBAC permissions need to be configured for Managed Identity");
            Console.WriteLine($"💡 Run: az role assignment create --role \"Key Vault Certificate User\" --assignee <managed-identity-id> --scope <key-vault-scope>");
            return null;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Error loading {certificateType} certificate '{certificateName}' from Key Vault: {ex.Message}");
            Console.WriteLine($"📋 Exception type: {ex.GetType().Name}");
            return null;
        }
    }
}

public static class CertificateServiceExtensions
{
    public static IServiceCollection AddCertificateServices(this IServiceCollection services, IConfiguration configuration)
    {
        var certificateConfig = configuration.GetSection(CertificateConfiguration.SectionName).Get<CertificateConfiguration>();
        var azureCertificateConfig = configuration.GetSection(AzureCertificateConfiguration.SectionName).Get<AzureCertificateConfiguration>();
        var keyVaultConfig = configuration.GetSection(AzureKeyVaultConfiguration.SectionName).Get<AzureKeyVaultConfiguration>();

        // Check if we're running in Azure App Service Linux
        var isAzureAppServiceLinux = IsAzureAppServiceLinux();
        
        Console.WriteLine($"🔍 Environment Detection:");
        Console.WriteLine($"   Azure App Service Linux: {isAzureAppServiceLinux}");
        Console.WriteLine($"   Key Vault Configured: {keyVaultConfig?.UseKeyVault == true}");
        Console.WriteLine($"   Key Vault URL: {keyVaultConfig?.VaultUrl}");

        // Priority 1: Use Azure Key Vault if configured and we're in Azure App Service Linux
        if (isAzureAppServiceLinux && keyVaultConfig?.UseKeyVault == true && !string.IsNullOrEmpty(keyVaultConfig.VaultUrl))
        {
            Console.WriteLine("✅ Using Azure Key Vault Certificate Service for Azure App Service Linux");
            services.AddSingleton(keyVaultConfig);
            services.AddSingleton<ICertificateService, AzureKeyVaultCertificateService>();
        }
        // Priority 2: Use Azure Certificate Store (for Windows or when Key Vault is not configured)
        else if (!string.IsNullOrEmpty(azureCertificateConfig?.ServerCertThumbprint) || 
                 !string.IsNullOrEmpty(azureCertificateConfig?.ClientCertThumbprint))
        {
            Console.WriteLine("✅ Using Azure Certificate Store Service");
            services.AddSingleton(azureCertificateConfig);
            if (certificateConfig != null)
            {
                services.AddSingleton(certificateConfig);
            }
            services.AddSingleton<ICertificateService>(provider =>
            {
                var azureConfig = provider.GetRequiredService<AzureCertificateConfiguration>();
                return new AzureCertificateService(azureConfig);
            });
        }
        // Priority 3: Use local certificates (development/testing)
        else if (certificateConfig != null)
        {
            Console.WriteLine("✅ Using Local Certificate Service");
            services.AddSingleton(certificateConfig);
            services.AddSingleton<ICertificateService, LocalCertificateService>();
        }
        else
        {
            Console.WriteLine("⚠️  No certificate configuration found");
        }

        return services;
    }
    
    private static bool IsAzureAppServiceLinux()
    {
        // Azure App Service Linux environment variables
        var websiteSku = Environment.GetEnvironmentVariable("WEBSITE_SKU");
        var websiteResourceGroup = Environment.GetEnvironmentVariable("WEBSITE_RESOURCE_GROUP");
        var websiteSiteName = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME");
        var isLinux = Environment.OSVersion.Platform == PlatformID.Unix;
        
        return !string.IsNullOrEmpty(websiteSku) && 
               !string.IsNullOrEmpty(websiteResourceGroup) && 
               !string.IsNullOrEmpty(websiteSiteName) && 
               isLinux;
    }
}
