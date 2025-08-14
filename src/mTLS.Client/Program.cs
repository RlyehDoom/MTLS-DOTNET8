using mTLS.Shared.Models;
using mTLS.Shared.Services;
using Microsoft.AspNetCore.Authentication.Certificate;
using Microsoft.AspNetCore.Server.Kestrel.Https;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using System.Net;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Add certificate services
builder.Services.AddCertificateServices(builder.Configuration);

// Enable HTTP/2 for HTTPS
builder.Services.Configure<KestrelServerOptions>(options =>
{
    options.ConfigureEndpointDefaults(endpointOptions =>
    {
        endpointOptions.Protocols = HttpProtocols.Http1AndHttp2;
    });
});

// Configure certificate authentication for the client server
builder.Services.AddAuthentication(CertificateAuthenticationDefaults.AuthenticationScheme)
    .AddCertificate(options =>
    {
        options.AllowedCertificateTypes = CertificateTypes.All;
        options.RevocationMode = System.Security.Cryptography.X509Certificates.X509RevocationMode.NoCheck;
        options.ValidateCertificateUse = false;
        options.ValidateValidityPeriod = false;
        
        options.Events = new CertificateAuthenticationEvents
        {
            OnCertificateValidated = context =>
            {
                Console.WriteLine($"Client certificate validated: {context.ClientCertificate.Subject}");
                context.Success();
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization();

// Configure Kestrel for HTTPS with client certificate
if (builder.Environment.IsDevelopment())
{
    Console.WriteLine("Running in Development mode - configuring Kestrel with HTTPS");
    builder.WebHost.ConfigureKestrel((context, serverOptions) =>
    {
        var certificateService = context.Configuration.GetSection(CertificateConfiguration.SectionName).Get<CertificateConfiguration>();
        
        if (certificateService != null)
        {
            var serviceProvider = builder.Services.BuildServiceProvider();
            var certService = serviceProvider.GetService<ICertificateService>();
            var serverCert = certService?.LoadServerCertificate(); // Usar certificado del servidor
            
            if (serverCert != null)
            {
                Console.WriteLine($"Using server certificate for HTTPS endpoint: {serverCert.Subject}");
                
                serverOptions.Listen(IPAddress.Any, 5000, listenOptions =>
                {
                    listenOptions.UseHttps(httpsOptions =>
                    {
                        httpsOptions.ServerCertificate = serverCert; // Usar certificado del servidor
                        httpsOptions.ClientCertificateMode = ClientCertificateMode.AllowCertificate;
                    });
                });
            }
        }
    });
}
else
{
    // Production mode - simulate Azure behavior with local certificates
    Console.WriteLine("Running in Production mode - simulating Azure client behavior");
    
    builder.WebHost.ConfigureKestrel((context, serverOptions) =>
    {
        var certificateService = context.Configuration.GetSection(CertificateConfiguration.SectionName).Get<CertificateConfiguration>();
        
        if (certificateService != null)
        {
            var serviceProvider = builder.Services.BuildServiceProvider();
            var certService = serviceProvider.GetService<ICertificateService>();
            var serverCert = certService?.LoadServerCertificate();
            
            if (serverCert != null)
            {
                Console.WriteLine($"Production mode - Using server certificate for HTTPS: {serverCert.Subject}");
                
                serverOptions.Listen(IPAddress.Any, 5000, listenOptions =>
                {
                    listenOptions.UseHttps(httpsOptions =>
                    {
                        httpsOptions.ServerCertificate = serverCert;
                        httpsOptions.ClientCertificateMode = ClientCertificateMode.AllowCertificate;
                    });
                });
            }
            else
            {
                Console.WriteLine("❌ Production mode - Server certificate not found for HTTPS");
            }
        }
        else
        {
            Console.WriteLine("❌ Production mode - Certificate configuration not found");
        }
    });
}

// Add HttpClient for mTLS testing
builder.Services.AddHttpClient("mTLSClient", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["ServerUrl"] ?? "https://localhost:5001");
})
.ConfigurePrimaryHttpMessageHandler(serviceProvider =>
{
    var certificateService = serviceProvider.GetService<ICertificateService>();
    var clientCert = certificateService?.LoadClientCertificate();
    
    var handler = new HttpClientHandler();
    
    if (clientCert != null)
    {
        handler.ClientCertificates.Add(clientCert);
        Console.WriteLine($"Client certificate loaded: {clientCert.Subject}");
    }
    
    // Certificate validation based on environment
    if (builder.Environment.IsDevelopment())
    {
        handler.ServerCertificateCustomValidationCallback = (message, cert, chain, sslPolicyErrors) =>
        {
            Console.WriteLine($"Development mode - Server cert subject: {cert?.Subject}");
            Console.WriteLine($"Development mode - Server cert issuer: {cert?.Issuer}");
            return true; // Accept any certificate in development
        };
    }
    else
    {
        // Production mode - more strict validation but still accept self-signed for local testing
        handler.ServerCertificateCustomValidationCallback = (message, cert, chain, sslPolicyErrors) =>
        {
            Console.WriteLine($"Production mode - Validating server certificate: {cert?.Subject}");
            Console.WriteLine($"Production mode - SSL Policy Errors: {sslPolicyErrors}");
            
            // In real Azure, this would use proper certificate validation
            // For local testing, we accept our self-signed certificates
            if (cert?.Subject?.Contains("Development MTLS") == true)
            {
                Console.WriteLine("Production mode - Accepting development certificate for local testing");
                return true;
            }
            
            return sslPolicyErrors == System.Net.Security.SslPolicyErrors.None;
        };
    }
    
    return handler;
});

var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();

// Client test endpoints
app.MapGet("/", () => "mTLS Test Client - Use /test-server to test mTLS connection");

app.MapGet("/test-server", async (IHttpClientFactory httpClientFactory) =>
{
    var client = httpClientFactory.CreateClient("mTLSClient");
    var results = new List<object>();
    
    // Test health endpoint (public)
    try
    {
        var healthResponse = await client.GetStringAsync("/health");
        results.Add(new { Endpoint = "/health", Status = "Success", Response = healthResponse });
    }
    catch (Exception ex)
    {
        results.Add(new { Endpoint = "/health", Status = "Failed", Error = ex.Message });
    }
    
    // Test weather forecast endpoint (public)
    try
    {
        var weatherResponse = await client.GetStringAsync("/weatherforecast");
        results.Add(new { Endpoint = "/weatherforecast", Status = "Success", Response = weatherResponse });
    }
    catch (Exception ex)
    {
        results.Add(new { Endpoint = "/weatherforecast", Status = "Failed", Error = ex.Message });
    }
    
    // Test mTLS endpoint (requires client certificate)
    try
    {
        var mtlsResponse = await client.GetStringAsync("/mtls-test");
        results.Add(new { Endpoint = "/mtls-test", Status = "Success", Response = mtlsResponse });
    }
    catch (Exception ex)
    {
        results.Add(new { Endpoint = "/mtls-test", Status = "Failed", Error = ex.Message });
    }
    
    return Results.Ok(new
    {
        TestResults = results,
        Timestamp = DateTime.UtcNow
    });
});

app.MapGet("/cert-info", (ICertificateService certificateService) =>
{
    var clientCert = certificateService.LoadClientCertificate();
    
    if (clientCert != null)
    {
        return Results.Ok(new
        {
            ClientCertificate = CertificateInfo.FromX509Certificate(clientCert),
            Message = "Client certificate loaded successfully"
        });
    }
    
    return Results.BadRequest(new { Message = "No client certificate available" });
});

Console.WriteLine("Starting mTLS Test Client...");
Console.WriteLine("Endpoints available:");
Console.WriteLine("- GET / (info)");
Console.WriteLine("- GET /test-server (test mTLS server)");
Console.WriteLine("- GET /cert-info (client certificate info)");

app.Run();
