using Microsoft.AspNetCore.Authentication.Certificate;
using Microsoft.AspNetCore.Server.Kestrel.Https;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.AspNetCore.HttpOverrides;
using mTLS.Shared.Models;
using mTLS.Shared.Services;
using mTLS.Server.Services;
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

// Configure authentication - Azure App Service handles TLS termination
// We'll validate certificates manually from X-ARR-ClientCert header
builder.Services.AddAuthentication("Bearer")
    .AddScheme<Microsoft.AspNetCore.Authentication.AuthenticationSchemeOptions, AzureAppServiceAuthenticationHandler>(
        "Bearer", options => { });

builder.Services.AddAuthorization(options =>
{
    // Policy for mTLS endpoints - requires valid client certificate
    options.AddPolicy("RequireClientCertificate", policy =>
        policy.RequireAuthenticatedUser());
});

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
    // Production mode - Azure App Service configuration
    Console.WriteLine("Running in Production mode - Azure App Service");
    
    // In Azure App Service, let Azure handle the port binding
    // Azure automatically configures Kestrel with the correct port
    Console.WriteLine("HTTPS termination handled by Azure Load Balancer");
    Console.WriteLine("Port configuration handled by Azure App Service");
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

// Serve static files from current directory (root) in Azure
app.UseDefaultFiles(new DefaultFilesOptions
{
    DefaultFileNames = { "index.html" }
});

app.UseStaticFiles(); // Serves from wwwroot by default

// Also serve static files from root directory for Azure deployment
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(
        Path.Combine(builder.Environment.ContentRootPath)),
    RequestPath = ""
});

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

// mTLS test endpoint (requires client certificate from Azure header)
app.MapGet("/mtls-test", (HttpContext context, ICertificateService certificateService) =>
{
    // Get client certificate from Azure App Service header
    var clientCert = AzureAppServiceCertificateHandler.GetClientCertificateFromHeader(context);
    
    if (clientCert != null)
    {
        return Results.Ok(new mTLSTestResponse
        {
            Message = "mTLS connection successful via Azure App Service!",
            ClientCertificate = CertificateInfo.FromX509Certificate(clientCert),
            Timestamp = DateTime.UtcNow
        });
    }
    
    return Results.BadRequest(new { 
        Message = "No client certificate provided", 
        Info = "Client certificate should be forwarded by Azure App Service in X-ARR-ClientCert header" 
    });
}).RequireAuthorization("RequireClientCertificate");

Console.WriteLine("Starting mTLS API server...");
Console.WriteLine("Endpoints available:");
Console.WriteLine("- GET /health (public)");
Console.WriteLine("- GET /mtls-test (requires client certificate)");
Console.WriteLine("- GET /weatherforecast (public)");

app.Run();