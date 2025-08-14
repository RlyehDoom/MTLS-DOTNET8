using Microsoft.AspNetCore.Authentication.Certificate;
using Microsoft.AspNetCore.Server.Kestrel.Https;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.AspNetCore.HttpOverrides;
using mTLS.Shared.Models;
using mTLS.Shared.Services;
using System.Net;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Add certificate services
builder.Services.AddCertificateServices(builder.Configuration);

// Configure forwarded headers for Azure Load Balancer
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

// Enable HTTP/2 only in Development with HTTPS or in Production (Azure handles it)
if (builder.Environment.IsDevelopment() || builder.Environment.IsProduction())
{
    builder.Services.Configure<KestrelServerOptions>(options =>
    {
        options.ConfigureEndpointDefaults(endpointOptions =>
        {
            endpointOptions.Protocols = HttpProtocols.Http1AndHttp2;
        });
    });
}

// Configure certificate authentication
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
            },
            OnAuthenticationFailed = context =>
            {
                Console.WriteLine($"Certificate authentication failed: {context.Exception?.Message}");
                context.Fail("Certificate authentication failed");
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization();

// Configure Kestrel for local development only
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
            var serverCert = certService?.LoadServerCertificate();
            
            if (serverCert != null)
            {
                Console.WriteLine($"Using server certificate: {serverCert.Subject}");
                
                serverOptions.Listen(IPAddress.Any, 5001, listenOptions =>
                {
                    listenOptions.UseHttps(httpsOptions =>
                    {
                        httpsOptions.ServerCertificate = serverCert;
                        httpsOptions.ClientCertificateMode = ClientCertificateMode.AllowCertificate;
                        httpsOptions.ClientCertificateValidation = (certificate, chain, errors) =>
                        {
                            if (certificate == null) return true;
                            
                            var isValid = certService?.ValidateClientCertificate(certificate) ?? false;
                            Console.WriteLine($"Certificate validation result: {isValid}");
                            Console.WriteLine($"Certificate subject: {certificate?.Subject}");
                            Console.WriteLine($"Certificate issuer: {certificate?.Issuer}");
                            
                            return isValid;
                        };
                    });
                });
            }
            else
            {
                Console.WriteLine("❌ Server certificate not found - using default HTTP configuration");
                serverOptions.Listen(IPAddress.Any, 5000);
            }
        }
        else
        {
            Console.WriteLine("❌ Certificate configuration not found - using default HTTP configuration");
            serverOptions.Listen(IPAddress.Any, 5000);
        }
    });
}
else
{
    // Production mode - simulate Azure behavior with local certificates for testing
    Console.WriteLine("Running in Production mode - simulating Azure with local certificates");
    
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
                Console.WriteLine($"Production mode - Using server certificate: {serverCert.Subject}");
                
                serverOptions.Listen(IPAddress.Any, 5001, listenOptions =>
                {
                    listenOptions.UseHttps(httpsOptions =>
                    {
                        httpsOptions.ServerCertificate = serverCert;
                        httpsOptions.ClientCertificateMode = ClientCertificateMode.RequireCertificate;
                        httpsOptions.ClientCertificateValidation = (certificate, chain, errors) =>
                        {
                            if (certificate == null) 
                            {
                                Console.WriteLine("Production mode - No client certificate provided");
                                return false;
                            }
                            
                            var isValid = certService?.ValidateClientCertificate(certificate) ?? false;
                            Console.WriteLine($"Production mode - Certificate validation: {isValid}");
                            Console.WriteLine($"Certificate subject: {certificate?.Subject}");
                            
                            return isValid;
                        };
                    });
                });
            }
            else
            {
                Console.WriteLine("❌ Production mode - Server certificate not found");
            }
        }
        else
        {
            Console.WriteLine("❌ Production mode - Certificate configuration not found");
        }
    });
}

var app = builder.Build();

// Configure forwarded headers (must be before UseAuthentication)
app.UseForwardedHeaders();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
else
{
    // In production, enforce HTTPS
    app.UseHsts();
}

app.UseHttpsRedirection();

app.UseAuthentication();
app.UseAuthorization();

// Health endpoint (public)
app.MapGet("/health", () => new HealthResponse 
{ 
    Status = "Healthy", 
    Timestamp = DateTime.UtcNow 
});

// Weather forecast endpoint (public)
app.MapGet("/weatherforecast", () =>
{
    var summaries = new[]
    {
        "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
    };

    var forecast = Enumerable.Range(1, 5).Select(index =>
        new WeatherForecast
        {
            Date = DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            TemperatureC = Random.Shared.Next(-20, 55),
            Summary = summaries[Random.Shared.Next(summaries.Length)]
        })
        .ToArray();
    return forecast;
})
.WithName("GetWeatherForecast")
.WithOpenApi();

// mTLS test endpoint (requires client certificate)
app.MapGet("/mtls-test", (HttpContext context) =>
{
    var clientCert = context.Connection.ClientCertificate;
    
    if (clientCert != null)
    {
        return Results.Ok(new mTLSTestResponse
        {
            Message = "mTLS connection successful!",
            ClientCertificate = CertificateInfo.FromX509Certificate(clientCert),
            Timestamp = DateTime.UtcNow
        });
    }
    
    return Results.BadRequest(new { Message = "No client certificate provided" });
}).RequireAuthorization();

Console.WriteLine("Starting mTLS API server...");
Console.WriteLine("Endpoints available:");
Console.WriteLine("- GET /health (public)");
Console.WriteLine("- GET /mtls-test (requires client certificate)");
Console.WriteLine("- GET /weatherforecast (public)");

app.Run();
