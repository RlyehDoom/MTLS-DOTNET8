using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using mTLS.Shared.Models;
using System.Security.Cryptography.X509Certificates;

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
    private readonly CertificateConfiguration _fallbackConfig;

    public AzureCertificateService(AzureCertificateConfiguration config, CertificateConfiguration fallbackConfig = null)
    {
        _config = config;
        _fallbackConfig = fallbackConfig;
    }

    public X509Certificate2? LoadServerCertificate()
    {
        var cert = LoadCertificateFromStore(_config.ServerCertThumbprint);
        if (cert == null && _fallbackConfig != null)
        {
            Console.WriteLine("🔄 Falling back to local certificate for server");
            return LoadLocalCertificate(_fallbackConfig.ServerCert, _fallbackConfig.ServerCertPassword);
        }
        return cert;
    }

    public X509Certificate2? LoadCACertificate()
    {
        var cert = LoadCertificateFromStore(_config.CACertThumbprint);
        if (cert == null && _fallbackConfig != null)
        {
            Console.WriteLine("🔄 Falling back to local certificate for CA");
            return LoadLocalCertificate(_fallbackConfig.CACert, null);
        }
        return cert;
    }

    public X509Certificate2? LoadClientCertificate()
    {
        var cert = LoadCertificateFromStore(_config.ClientCertThumbprint);
        if (cert == null && _fallbackConfig != null)
        {
            Console.WriteLine("🔄 Falling back to local certificate for client");
            return LoadLocalCertificate(_fallbackConfig.ClientCert, _fallbackConfig.ClientCertPassword);
        }
        return cert;
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

public static class CertificateServiceExtensions
{
    public static IServiceCollection AddCertificateServices(this IServiceCollection services, IConfiguration configuration)
    {
        var certificateConfig = configuration.GetSection(CertificateConfiguration.SectionName).Get<CertificateConfiguration>();
        var azureCertificateConfig = configuration.GetSection(AzureCertificateConfiguration.SectionName).Get<AzureCertificateConfiguration>();

        // Usar Azure Certificate Service si estamos en Azure y hay configuración
        if (!string.IsNullOrEmpty(azureCertificateConfig?.ServerCertThumbprint) || 
            !string.IsNullOrEmpty(azureCertificateConfig?.ClientCertThumbprint))
        {
            services.AddSingleton(azureCertificateConfig);
            if (certificateConfig != null)
            {
                services.AddSingleton(certificateConfig);
            }
            services.AddSingleton<ICertificateService>(provider =>
            {
                var azureConfig = provider.GetRequiredService<AzureCertificateConfiguration>();
                var fallbackConfig = provider.GetService<CertificateConfiguration>();
                return new AzureCertificateService(azureConfig, fallbackConfig);
            });
        }
        else if (certificateConfig != null)
        {
            services.AddSingleton(certificateConfig);
            services.AddSingleton<ICertificateService, LocalCertificateService>();
        }

        return services;
    }
}
