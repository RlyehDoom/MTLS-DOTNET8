using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;
using mTLS.Shared.Services;
using System.Security.Claims;
using System.Text.Encodings.Web;

namespace mTLS.Server.Services;

public class AzureAppServiceAuthenticationHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    private readonly ICertificateService _certificateService;

    public AzureAppServiceAuthenticationHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder,
        ICertificateService certificateService) 
        : base(options, logger, encoder)
    {
        _certificateService = certificateService;
    }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        try
        {
            // For public endpoints, we don't require authentication
            var path = Context.Request.Path.Value?.ToLowerInvariant();
            if (path == "/health" || path == "/weatherforecast")
            {
                // Public endpoint - no authentication required
                return Task.FromResult(AuthenticateResult.NoResult());
            }

            // For mTLS endpoints, validate client certificate from header
            if (path == "/mtls-test")
            {
                // Check if request is from Azure App Service
                if (!AzureAppServiceCertificateHandler.IsFromAzureAppService(Context))
                {
                    Logger.LogWarning("Request not from Azure App Service");
                    return Task.FromResult(AuthenticateResult.Fail("Request not from Azure App Service"));
                }

                // Get client certificate from Azure header
                var clientCert = AzureAppServiceCertificateHandler.GetClientCertificateFromHeader(Context);
                if (clientCert == null)
                {
                    Logger.LogWarning("No client certificate found in X-ARR-ClientCert header");
                    return Task.FromResult(AuthenticateResult.Fail("No client certificate provided"));
                }

                // Validate the certificate
                var isValid = AzureAppServiceCertificateHandler.ValidateClientCertificate(clientCert, _certificateService);
                if (!isValid)
                {
                    Logger.LogWarning("Client certificate validation failed");
                    return Task.FromResult(AuthenticateResult.Fail("Invalid client certificate"));
                }

                // Create claims for successful authentication
                var claims = new[]
                {
                    new Claim(ClaimTypes.Name, clientCert.Subject),
                    new Claim("certificate-thumbprint", clientCert.Thumbprint),
                    new Claim("certificate-issuer", clientCert.Issuer)
                };

                var identity = new ClaimsIdentity(claims, Scheme.Name);
                var principal = new ClaimsPrincipal(identity);
                var ticket = new AuthenticationTicket(principal, Scheme.Name);

                Logger.LogInformation($"Successfully authenticated client certificate: {clientCert.Subject}");
                return Task.FromResult(AuthenticateResult.Success(ticket));
            }

            // For other endpoints, no authentication required by default
            return Task.FromResult(AuthenticateResult.NoResult());
        }
        catch (Exception ex)
        {
            Logger.LogError(ex, "Error in authentication handler");
            return Task.FromResult(AuthenticateResult.Fail("Authentication error"));
        }
    }
}