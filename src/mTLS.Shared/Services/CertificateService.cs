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
        if (string.IsNullOrEmpty(thumbprint)) return null;

        using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
        store.Open(OpenFlags.ReadOnly);

        var certificates = store.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false);
        return certificates.Count > 0 ? certificates[0] : null;
    }
}

public static class CertificateServiceExtensions
{
    public static IServiceCollection AddCertificateServices(this IServiceCollection services, IConfiguration configuration)
    {
        var certificateConfig = configuration.GetSection(CertificateConfiguration.SectionName).Get<CertificateConfiguration>();
        var azureCertificateConfig = configuration.GetSection(AzureCertificateConfiguration.SectionName).Get<AzureCertificateConfiguration>();

        // Usar Azure Certificate Service si estamos en Azure y hay configuración
        if (!string.IsNullOrEmpty(azureCertificateConfig?.ServerCertThumbprint))
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
