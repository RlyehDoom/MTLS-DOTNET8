# Script para obtener thumbprints de certificados
# Útil para configurar los scripts de deployment de Azure

param(
    [string]$CertsPath = "",
    [switch]$ShowDetails
)

# Determinar ruta base del script
$ScriptDir = $PSScriptRoot
$ProjectRoot = Split-Path $ScriptDir -Parent

# Usar ruta relativa si no se especifica
if ([string]::IsNullOrEmpty($CertsPath)) {
    $CertsPath = Join-Path $ProjectRoot "Certs"
}

Write-Host "🔍 Obteniendo thumbprints de certificados..." -ForegroundColor Green
Write-Host "Script Directory: $ScriptDir" -ForegroundColor Gray
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Gray
Write-Host "Certificates Path: $CertsPath" -ForegroundColor Gray
Write-Host ""

function Get-CertificateThumbprint {
    param(
        [string]$CertPath,
        [string]$Password = "",
        [string]$CertName
    )
    
    if (-not (Test-Path $CertPath)) {
        Write-Host "❌ $CertName no encontrado: $CertPath" -ForegroundColor Red
        return $null
    }
    
    try {
        $resolvedPath = Resolve-Path $CertPath -ErrorAction Stop
        if ($CertPath.EndsWith(".pfx")) {
            # Certificado PFX con contraseña
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($resolvedPath.Path, $Password)
        } else {
            # Certificado CRT sin contraseña
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($resolvedPath.Path)
        }
        
        Write-Host "✅ $CertName" -ForegroundColor Green
        Write-Host "   Archivo: $CertPath" -ForegroundColor Gray
        Write-Host "   Thumbprint: $($cert.Thumbprint)" -ForegroundColor Cyan
        
        if ($ShowDetails) {
            Write-Host "   Subject: $($cert.Subject)" -ForegroundColor Yellow
            Write-Host "   Issuer: $($cert.Issuer)" -ForegroundColor Yellow
            Write-Host "   Válido desde: $($cert.NotBefore)" -ForegroundColor Yellow
            Write-Host "   Válido hasta: $($cert.NotAfter)" -ForegroundColor Yellow
            Write-Host "   Tiene clave privada: $($cert.HasPrivateKey)" -ForegroundColor Yellow
        }
        
        Write-Host ""
        return $cert.Thumbprint
        
    } catch {
        Write-Host "❌ Error al cargar $CertName : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return $null
    }
}

# Certificados a verificar
$serverCertPath = Join-Path $CertsPath "dev-env.pfx"
$caCertPath = Join-Path $CertsPath "ca.crt"
$clientCertPath = Join-Path $CertsPath "dev-env_client.pfx"

# Obtener thumbprints
$serverThumbprint = Get-CertificateThumbprint -CertPath $serverCertPath -Password "Developer2077" -CertName "Certificado Servidor"
$caThumbprint = Get-CertificateThumbprint -CertPath $caCertPath -CertName "Certificado CA"
$clientThumbprint = Get-CertificateThumbprint -CertPath $clientCertPath -Password "Developer2077" -CertName "Certificado Cliente"

# Resumen para deployment
Write-Host "📋 Resumen de Thumbprints para Azure Deployment:" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

if ($serverThumbprint) {
    Write-Host "SERVER_CERT_THUMBPRINT=$serverThumbprint" -ForegroundColor White
}
if ($caThumbprint) {
    Write-Host "CA_CERT_THUMBPRINT=$caThumbprint" -ForegroundColor White
}
if ($clientThumbprint) {
    Write-Host "CLIENT_CERT_THUMBPRINT=$clientThumbprint" -ForegroundColor White
}

Write-Host ""
Write-Host "💡 Comandos para deployment:" -ForegroundColor Yellow
Write-Host ""

if ($serverThumbprint -and $caThumbprint -and $clientThumbprint) {
    Write-Host "# Deployment completo:" -ForegroundColor Green
    Write-Host ".\deploy-complete.ps1 ``" -ForegroundColor White
    Write-Host "    -ServerCertThumbprint `"$serverThumbprint`" ``" -ForegroundColor White
    Write-Host "    -CACertThumbprint `"$caThumbprint`" ``" -ForegroundColor White
    Write-Host "    -ClientCertThumbprint `"$clientThumbprint`"" -ForegroundColor White
    Write-Host ""
    
    Write-Host "# Solo recursos Azure:" -ForegroundColor Green
    Write-Host ".\deploy-azure.ps1 ``" -ForegroundColor White
    Write-Host "    -ServerCertThumbprint `"$serverThumbprint`" ``" -ForegroundColor White
    Write-Host "    -CACertThumbprint `"$caThumbprint`" ``" -ForegroundColor White
    Write-Host "    -ClientCertThumbprint `"$clientThumbprint`"" -ForegroundColor White
}

# Generar archivo de configuración
$configFile = "thumbprints-config.json"
$config = @{
    ServerCertThumbprint = $serverThumbprint
    CACertThumbprint = $caThumbprint
    ClientCertThumbprint = $clientThumbprint
    GeneratedDate = Get-Date
    CertificatesPath = $CertsPath
} | ConvertTo-Json -Depth 2

$config | Out-File $configFile -Encoding UTF8
Write-Host "📄 Configuración guardada en: $configFile" -ForegroundColor Green

# Comandos adicionales útiles
Write-Host ""
Write-Host "🔧 Comandos útiles adicionales:" -ForegroundColor Yellow
Write-Host ""
Write-Host "# Verificar certificado en Azure (después de subir):" -ForegroundColor Gray
if ($serverThumbprint) {
    Write-Host "az webapp config ssl list --resource-group rg-mtls-demo --query `"[?thumbprint=='$serverThumbprint']`"" -ForegroundColor Gray
}
Write-Host ""
Write-Host "# Subir certificados a Azure App Service:" -ForegroundColor Gray
Write-Host "az webapp config ssl upload --resource-group rg-mtls-demo --name your-app-name --certificate-file `"$serverCertPath`" --certificate-password `"Developer2077`"" -ForegroundColor Gray
Write-Host "az webapp config ssl upload --resource-group rg-mtls-demo --name your-app-name --certificate-file `"$clientCertPath`" --certificate-password `"Developer2077`"" -ForegroundColor Gray
