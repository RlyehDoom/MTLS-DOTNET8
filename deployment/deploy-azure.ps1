# Azure deployment script for mTLS Server and Client (PowerShell)
# Prerequisites: Azure CLI installed and logged in

param(
    [string]$ResourceGroup = "rg-mtls-demo",
    [string]$Location = "East US",
    [string]$ServerAppName = "mtls-server",
    [string]$ClientAppName = "mtls-client",
    [string]$ServerCertThumbprint = "A37AB3C30590D3944F48438DC4E40A475C561F02",
    [string]$CACertThumbprint = "DD33C9FDA8AF3A298B560D732E50590E57A89326",
    [string]$ClientCertThumbprint = "7C63CEC64CB152CB0E06BF058C91506830A5568F"
)

# Use provided names or generate predictable ones
if ([string]::IsNullOrEmpty($ServerAppName)) {
    $ServerAppName = "mtls-server"
}
if ([string]::IsNullOrEmpty($ClientAppName)) {
    $ClientAppName = "mtls-client"
}
$AppServicePlan = "asp-mtls-demo"

Write-Host "🚀 Starting Azure deployment for mTLS demo..." -ForegroundColor Green

# Create resource group
Write-Host "📦 Creating resource group: $ResourceGroup" -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location

# Create App Service Plan
Write-Host "🏗️ Creating App Service Plan: $AppServicePlan" -ForegroundColor Yellow
az appservice plan create `
    --name $AppServicePlan `
    --resource-group $ResourceGroup `
    --sku S1 `
    --is-linux

# Create Server Web App
Write-Host "🖥️ Creating Server Web App: $ServerAppName" -ForegroundColor Yellow
az webapp create `
    --resource-group $ResourceGroup `
    --plan $AppServicePlan `
    --name $ServerAppName `
    --runtime "DOTNETCORE:8.0"

# Create Client Web App
Write-Host "💻 Creating Client Web App: $ClientAppName" -ForegroundColor Yellow
az webapp create `
    --resource-group $ResourceGroup `
    --plan $AppServicePlan `
    --name $ClientAppName `
    --runtime "DOTNETCORE:8.0"

# Configure Server App Settings
Write-Host "⚙️ Configuring Server App Settings..." -ForegroundColor Yellow
az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $ServerAppName `
    --settings `
        "ASPNETCORE_ENVIRONMENT=Production" `
        "ASPNETCORE_FORWARDEDHEADERS_ENABLED=true" `
        "ASPNETCORE_HTTPS_PORT=443" `
        "AzureCertificates__ServerCertThumbprint=$ServerCertThumbprint" `
        "AzureCertificates__CACertThumbprint=$CACertThumbprint" `
        "AzureCertificates__ClientCertThumbprint=$ClientCertThumbprint"

# Enable client certificates for the server app
Write-Host "🔒 Enabling client certificate authentication..." -ForegroundColor Yellow
az webapp update `
    --resource-group $ResourceGroup `
    --name $ServerAppName `
    --set clientCertEnabled=true `
    --set clientCertMode=Required

# Configure HTTP/2
Write-Host "🚀 Enabling HTTP/2..." -ForegroundColor Yellow
az webapp config set `
    --resource-group $ResourceGroup `
    --name $ServerAppName `
    --http20-enabled true

# Configure Client App Settings
$ServerUrl = "https://$ServerAppName.azurewebsites.net"
Write-Host "⚙️ Configuring Client App Settings..." -ForegroundColor Yellow
az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $ClientAppName `
    --settings `
        "ASPNETCORE_ENVIRONMENT=Production" `
        "ASPNETCORE_FORWARDEDHEADERS_ENABLED=true" `
        "ASPNETCORE_HTTPS_PORT=443" `
        "ServerUrl=$ServerUrl" `
        "AzureCertificates__ClientCertThumbprint=$ClientCertThumbprint"

# Configure HTTP/2 for client app
Write-Host "🚀 Enabling HTTP/2 for client..." -ForegroundColor Yellow
az webapp config set `
    --resource-group $ResourceGroup `
    --name $ClientAppName `
    --http20-enabled true

# Enable HTTPS Only
Write-Host "🔒 Enabling HTTPS Only for both apps..." -ForegroundColor Yellow
az webapp update --resource-group $ResourceGroup --name $ServerAppName --https-only true
az webapp update --resource-group $ResourceGroup --name $ClientAppName --https-only true

# Output results
Write-Host "🌐 Apps created successfully!" -ForegroundColor Green
Write-Host "Server URL: https://$ServerAppName.azurewebsites.net" -ForegroundColor Cyan
Write-Host "Client URL: https://$ClientAppName.azurewebsites.net" -ForegroundColor Cyan

Write-Host ""
Write-Host "📋 Next steps:" -ForegroundColor Green
Write-Host "1. Upload your certificates to Azure App Service Certificate Store"
Write-Host "2. Verify the certificate thumbprints match the configuration"
Write-Host "3. Deploy your applications using the deploy scripts"
Write-Host "4. Configure custom domains if needed"
Write-Host "5. Test the mTLS functionality and HTTP/2 support"

Write-Host ""
Write-Host "💡 Certificate upload commands:" -ForegroundColor Yellow
Write-Host "# Upload server certificate:"
Write-Host "az webapp config ssl upload --resource-group $ResourceGroup --name $ServerAppName --certificate-file path/to/server.pfx --certificate-password 'your-password'"
Write-Host ""
Write-Host "# Upload client certificate (for testing):"
Write-Host "az webapp config ssl upload --resource-group $ResourceGroup --name $ClientAppName --certificate-file path/to/client.pfx --certificate-password 'your-password'"
Write-Host ""
Write-Host "🔍 Verification commands:" -ForegroundColor Yellow
Write-Host "# Check HTTP/2 support:"
Write-Host "curl -I --http2 https://$ServerAppName.azurewebsites.net/health"
Write-Host ""
Write-Host "# Test mTLS endpoint:"
Write-Host "curl --cert client.pem --key client.key https://$ServerAppName.azurewebsites.net/mtls-test"

# Create deployment info file
$deploymentInfo = @{
    ResourceGroup = $ResourceGroup
    ServerAppName = $ServerAppName
    ClientAppName = $ClientAppName
    ServerUrl = $ServerUrl
    ClientUrl = "https://$ClientAppName.azurewebsites.net"
    ServerCertThumbprint = $ServerCertThumbprint
    CACertThumbprint = $CACertThumbprint
    ClientCertThumbprint = $ClientCertThumbprint
    Timestamp = Get-Date
    Location = $Location
    AppServicePlan = $AppServicePlan
} | ConvertTo-Json -Depth 2

$deploymentInfo | Out-File "deployment-info.json" -Encoding UTF8
Write-Host "📄 Deployment info saved to deployment-info.json" -ForegroundColor Green
