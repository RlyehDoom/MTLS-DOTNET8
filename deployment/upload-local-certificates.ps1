# Script para subir certificados a Azure App Service
param(
    [string]$ResourceGroup = "rg-mtls-demo",
    [string]$ServerAppName = "mtls-server",
    [string]$ClientAppName = "mtls-client",
    [string]$CertPath = ""
)

# Determinar ruta base del script
$ScriptDir = $PSScriptRoot
$ProjectRoot = Split-Path $ScriptDir -Parent

# Usar ruta relativa si no se especifica - usar certificados existentes del servidor
if ([string]::IsNullOrEmpty($CertPath)) {
    $CertPath = Join-Path $ProjectRoot "src\mTLS.Server\Certs"
}

Write-Host "📤 Subiendo certificados locales a Azure App Service..." -ForegroundColor Green
Write-Host "Script Directory: $ScriptDir" -ForegroundColor Gray
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Gray
Write-Host "Certificates Path: $CertPath" -ForegroundColor Gray
Write-Host ""

# Cambiar al directorio de certificados
Set-Location $CertPath

# Certificados locales existentes
$serverCert = "dev-env.pfx"
$clientCert = "dev-env_client.pfx"

if (!(Test-Path $serverCert)) {
    Write-Host "❌ Error: $serverCert not found!" -ForegroundColor Red
    exit 1
}

if (!(Test-Path $clientCert)) {
    Write-Host "❌ Error: $clientCert not found!" -ForegroundColor Red
    exit 1
}

# 1. Upload server certificate
Write-Host "📋 Uploading server certificate..." -ForegroundColor Cyan
$serverCertResult = az webapp config ssl upload `
    --certificate-file $serverCert `
    --certificate-password "" `
    --name $ServerAppName `
    --resource-group $ResourceGroup `
    --query thumbprint `
    --output tsv

Write-Host "Server certificate uploaded with thumbprint: $serverCertResult" -ForegroundColor Green

# 2. Upload client certificate (CA cert for validation)
Write-Host "📋 Uploading client certificate..." -ForegroundColor Cyan
$clientCertResult = az webapp config ssl upload `
    --certificate-file $clientCert `
    --certificate-password "" `
    --name $ServerAppName `
    --resource-group $ResourceGroup `
    --query thumbprint `
    --output tsv

Write-Host "Client certificate uploaded with thumbprint: $clientCertResult" -ForegroundColor Green

# 3. Configure app settings with new thumbprints
Write-Host "📋 Updating app settings..." -ForegroundColor Cyan

# Extraer thumbprints directamente de los certificados locales
Write-Host "📋 Extracting thumbprints from local certificates..." -ForegroundColor Cyan
$serverThumbprint = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($serverCert, "Developer2077")).Thumbprint
$clientThumbprint = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($clientCert, "Developer2077")).Thumbprint

Write-Host "Server Certificate Thumbprint: $serverThumbprint" -ForegroundColor Yellow
Write-Host "Client Certificate Thumbprint: $clientThumbprint" -ForegroundColor Yellow

# Update server app settings
az webapp config appsettings set `
    --name $ServerAppName `
    --resource-group $ResourceGroup `
    --settings `
        "ServerCertificateThumbprint=$serverThumbprint" `
        "ClientCertificateThumbprint=$clientThumbprint" `
        "ASPNETCORE_ENVIRONMENT=Production"

# Update client app settings (if exists)
$clientExists = az webapp show --name $ClientAppName --resource-group $ResourceGroup --query name --output tsv 2>$null
if ($clientExists) {
    Write-Host "📋 Updating client app settings..." -ForegroundColor Cyan
    az webapp config appsettings set `
        --name $ClientAppName `
        --resource-group $ResourceGroup `
        --settings `
            "ServerCertificateThumbprint=$serverThumbprint" `
            "ClientCertificateThumbprint=$clientThumbprint" `
            "ASPNETCORE_ENVIRONMENT=Production"
}

Write-Host ""
Write-Host "✅ Certificados locales subidos exitosamente!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Resumen:" -ForegroundColor Yellow
Write-Host "Server App: $ServerAppName" -ForegroundColor White
Write-Host "Server Thumbprint: $serverThumbprint" -ForegroundColor White
Write-Host "Client Thumbprint: $clientThumbprint" -ForegroundColor White
Write-Host ""
Write-Host "📋 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Deploy applications to Azure" -ForegroundColor White
Write-Host "2. Test mTLS connection" -ForegroundColor White
Write-Host "3. Verify endpoints functionality" -ForegroundColor White
