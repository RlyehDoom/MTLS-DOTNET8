# Script para verificar el flujo completo de deployment
param(
    [switch]$DryRun,
    [string]$ResourceGroup = "rg-mtls-demo"
)

# Establecer DryRun como true por defecto si no se especifica
if (-not $PSBoundParameters.ContainsKey('DryRun')) {
    $DryRun = $true
}

Write-Host "🔍 Verificando flujo completo de deployment..." -ForegroundColor Green
Write-Host "Dry Run: $DryRun" -ForegroundColor Gray
Write-Host ""

# Determinar ruta base del script
$ScriptDir = $PSScriptRoot
$ProjectRoot = Split-Path $ScriptDir -Parent

# Variables por defecto
$ServerCertThumbprint = "A37AB3C30590D3944F48438DC4E40A475C561F02"
$ClientCertThumbprint = "7C63CEC64CB152CB0E06BF058C91506830A5568F"
$ServerAppName = "mtls-server"
$ClientAppName = "mtls-client"

Write-Host "📋 Configuración del deployment:" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "Server App: $ServerAppName" -ForegroundColor White
Write-Host "Client App: $ClientAppName" -ForegroundColor White
Write-Host "Server Thumbprint: $ServerCertThumbprint" -ForegroundColor White
Write-Host "Client Thumbprint: $ClientCertThumbprint" -ForegroundColor White
Write-Host ""

# 1. Verificar que los scripts existen
Write-Host "🔧 Verificando scripts de deployment..." -ForegroundColor Yellow

$Scripts = @(
    "deploy-azure.ps1",
    "upload-local-certificates.ps1", 
    "deploy-server.ps1",
    "deploy-client.ps1",
    "deploy-complete.ps1"
)

foreach ($script in $Scripts) {
    $scriptPath = Join-Path $ScriptDir $script
    if (Test-Path $scriptPath) {
        Write-Host "✅ $script" -ForegroundColor Green
    } else {
        Write-Host "❌ $script" -ForegroundColor Red
    }
}

# 2. Verificar certificados
Write-Host ""
Write-Host "🔐 Verificando certificados..." -ForegroundColor Yellow

$CertPath = Join-Path $ProjectRoot "src\mTLS.Server\Certs"
$ServerCert = Join-Path $CertPath "dev-env.pfx"
$ClientCert = Join-Path $CertPath "dev-env_client.pfx"

if (Test-Path $ServerCert) {
    Write-Host "✅ Server certificate: dev-env.pfx" -ForegroundColor Green
    $actualServerThumb = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ServerCert, "Developer2077")).Thumbprint
    Write-Host "   Thumbprint: $actualServerThumb" -ForegroundColor Gray
    if ($actualServerThumb -eq $ServerCertThumbprint) {
        Write-Host "   ✅ Matches default thumbprint" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️ Different from default thumbprint" -ForegroundColor Yellow
    }
} else {
    Write-Host "❌ Server certificate not found" -ForegroundColor Red
}

if (Test-Path $ClientCert) {
    Write-Host "✅ Client certificate: dev-env_client.pfx" -ForegroundColor Green
    $actualClientThumb = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ClientCert, "Developer2077")).Thumbprint
    Write-Host "   Thumbprint: $actualClientThumb" -ForegroundColor Gray
    if ($actualClientThumb -eq $ClientCertThumbprint) {
        Write-Host "   ✅ Matches default thumbprint" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️ Different from default thumbprint" -ForegroundColor Yellow
    }
} else {
    Write-Host "❌ Client certificate not found" -ForegroundColor Red
}

# 3. Verificar proyectos
Write-Host ""
Write-Host "🏗️ Verificando proyectos..." -ForegroundColor Yellow

$ServerProject = Join-Path $ProjectRoot "src\mTLS.Server\mTLS.Server.csproj"
$ClientProject = Join-Path $ProjectRoot "src\mTLS.Client\mTLS.Client.csproj"
$SharedProject = Join-Path $ProjectRoot "src\mTLS.Shared\mTLS.Shared.csproj"

if (Test-Path $ServerProject) {
    Write-Host "✅ Server project: mTLS.Server.csproj" -ForegroundColor Green
} else {
    Write-Host "❌ Server project not found" -ForegroundColor Red
}

if (Test-Path $ClientProject) {
    Write-Host "✅ Client project: mTLS.Client.csproj" -ForegroundColor Green
} else {
    Write-Host "❌ Client project not found" -ForegroundColor Red
}

if (Test-Path $SharedProject) {
    Write-Host "✅ Shared project: mTLS.Shared.csproj" -ForegroundColor Green
} else {
    Write-Host "❌ Shared project not found" -ForegroundColor Red
}

# 4. Verificar configuración de producción
Write-Host ""
Write-Host "⚙️ Verificando configuración de producción..." -ForegroundColor Yellow

$ServerProdSettings = Join-Path $ProjectRoot "src\mTLS.Server\appsettings.Production.json"
$ClientProdSettings = Join-Path $ProjectRoot "src\mTLS.Client\appsettings.Production.json"

if (Test-Path $ServerProdSettings) {
    Write-Host "✅ Server production settings" -ForegroundColor Green
} else {
    Write-Host "❌ Server production settings not found" -ForegroundColor Red
}

if (Test-Path $ClientProdSettings) {
    Write-Host "✅ Client production settings" -ForegroundColor Green
} else {
    Write-Host "❌ Client production settings not found" -ForegroundColor Red
}

Write-Host ""
Write-Host "📋 Orden de ejecución del deployment:" -ForegroundColor Cyan
Write-Host "1. deploy-azure.ps1 - Crear recursos de Azure" -ForegroundColor White
Write-Host "2. upload-local-certificates.ps1 - Subir certificados" -ForegroundColor White
Write-Host "3. deploy-server.ps1 - Deploy aplicación servidor" -ForegroundColor White
Write-Host "4. deploy-client.ps1 - Deploy aplicación cliente" -ForegroundColor White
Write-Host ""
Write-Host "🚀 Para ejecutar el deployment completo:" -ForegroundColor Green
Write-Host "   .\deploy-complete.ps1" -ForegroundColor Yellow
Write-Host ""

if ($DryRun) {
    Write-Host "✅ Verificación completada (DRY RUN)" -ForegroundColor Green
} else {
    Write-Host "⚠️ Usar -DryRun:$false para ejecutar deployment real" -ForegroundColor Yellow
}
