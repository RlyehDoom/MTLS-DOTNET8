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

    public AzureCertificateService(AzureCertificateConfiguration config)
    {
        _config = config;
    }

    public X509Certificate2? LoadServerCertificate()
    {
        return LoadCertificateFromStore(_config.ServerCertThumbprint);
    }

    public X509Certificate2? LoadCACertificate()
    {
        return LoadCertificateFromStore(_config.CACertThumbprint);
    }

    public X509Certificate2? LoadClientCertificate()
    {
        return LoadCertificateFromStore(_config.ClientCertThumbprint);
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
            // The format is: WEBSITE_LOAD_USER_PROFILE + specific certificate access
            var websiteLoadCerts = Environment.GetEnvironmentVariable("WEBSITE_LOAD_CERTIFICATES");
            Console.WriteLine($"🔧 WEBSITE_LOAD_CERTIFICATES: {websiteLoadCerts}");

            if (string.IsNullOrEmpty(websiteLoadCerts))
            {
                Console.WriteLine("❌ WEBSITE_LOAD_CERTIFICATES not set");
                return null;
            }

            // In Azure App Service Linux, certificates are loaded into a specific location
            // Let's try the CurrentUser store with different approaches
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
            services.AddSingleton<ICertificateService, AzureCertificateService>();
        }
        else if (certificateConfig != null)
        {
            services.AddSingleton(certificateConfig);
            services.AddSingleton<ICertificateService, LocalCertificateService>();
        }

        return services;
    }
}
