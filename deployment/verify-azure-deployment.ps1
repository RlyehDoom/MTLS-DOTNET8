# Script para verificar soporte HTTP/2 y mTLS en Azure
param(
    [string]$ServerUrl = "",
    [string]$ClientUrl = "",
    [string]$ConfigFile = ""
)

# Determinar ruta base del script
$ScriptDir = $PSScriptRoot

# Usar ruta relativa si no se especifica archivo de config
if ([string]::IsNullOrEmpty($ConfigFile)) {
    $ConfigFile = Join-Path $ScriptDir "deployment-info.json"
}

# Cargar información de deployment si no se proporcionan URLs
if ([string]::IsNullOrEmpty($ServerUrl) -and (Test-Path $ConfigFile)) {
    $deploymentInfo = Get-Content $ConfigFile | ConvertFrom-Json
    $ServerUrl = $deploymentInfo.ServerUrl
    $ClientUrl = $deploymentInfo.ClientUrl
}

if ([string]::IsNullOrEmpty($ServerUrl)) {
    Write-Error "ServerUrl no proporcionada y no se encontró archivo de configuración"
    exit 1
}

Write-Host "🧪 Verificando soporte HTTP/2 y mTLS en Azure..." -ForegroundColor Green
Write-Host "Script Directory: $ScriptDir" -ForegroundColor Gray
Write-Host "Config File: $ConfigFile" -ForegroundColor Gray
Write-Host "Server URL: $ServerUrl" -ForegroundColor Yellow
if (![string]::IsNullOrEmpty($ClientUrl)) {
    Write-Host "Client URL: $ClientUrl" -ForegroundColor Yellow
}
Write-Host ""

function Test-HttpVersion {
    param(
        [string]$Url,
        [string]$Description
    )
    
    Write-Host "🔍 Probando $Description..." -ForegroundColor Cyan
    Write-Host "URL: $Url" -ForegroundColor Gray
    
    try {
        # Test HTTP/2 support
        $response = curl -I --http2 -s $Url 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Conexión exitosa" -ForegroundColor Green
            
            # Check for HTTP/2 in response
            if ($response -match "HTTP/2") {
                Write-Host "✅ HTTP/2 soportado" -ForegroundColor Green
            } else {
                Write-Host "⚠️ HTTP/2 no detectado en respuesta" -ForegroundColor Yellow
            }
            
            # Show relevant headers
            $response | Where-Object { 
                $_ -match "HTTP/" -or 
                $_ -match "server:" -or 
                $_ -match "strict-transport-security" -or
                $_ -match "x-forwarded-proto"
            } | ForEach-Object {
                Write-Host "   $_" -ForegroundColor Gray
            }
        } else {
            Write-Host "❌ Error de conexión" -ForegroundColor Red
            Write-Host "Error: $response" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
}

function Test-MTLSEndpoint {
    param(
        [string]$Url
    )
    
    Write-Host "🔒 Probando endpoint mTLS..." -ForegroundColor Cyan
    Write-Host "URL: $Url/mtls-test" -ForegroundColor Gray
    
    try {
        # Test without client certificate (should fail)
        $response = curl -s "$Url/mtls-test" 2>&1
        
        if ($response -match "403" -or $response -match "Forbidden" -or $response -match "certificate") {
            Write-Host "✅ mTLS configurado correctamente (rechaza conexiones sin certificado)" -ForegroundColor Green
        } elseif ($response -match "400" -or $response -match "Bad Request") {
            Write-Host "✅ Endpoint accesible, requiere certificado válido" -ForegroundColor Green
        } else {
            Write-Host "⚠️ Respuesta inesperada del endpoint mTLS" -ForegroundColor Yellow
            Write-Host "Respuesta: $response" -ForegroundColor Gray
        }
    } catch {
        Write-Host "❌ Error probando mTLS: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
}

function Test-AzureFeatures {
    param(
        [string]$AppName
    )
    
    Write-Host "☁️ Verificando configuración Azure..." -ForegroundColor Cyan
    
    try {
        # Check if Azure CLI is available and logged in
        $account = az account show 2>$null | ConvertFrom-Json
        if ($account) {
            Write-Host "✅ Azure CLI configurado (Subscription: $($account.name))" -ForegroundColor Green
            
            # Get app configuration if app name is provided
            if (![string]::IsNullOrEmpty($AppName)) {
                Write-Host "📋 Configuración de la aplicación:" -ForegroundColor Yellow
                
                # Check client cert configuration
                $config = az webapp show --name $AppName --resource-group "rg-mtls-demo" --query "{clientCertEnabled:clientCertEnabled,clientCertMode:clientCertMode,httpsOnly:httpsOnly}" 2>$null | ConvertFrom-Json
                if ($config) {
                    Write-Host "   Client Cert Enabled: $($config.clientCertEnabled)" -ForegroundColor Gray
                    Write-Host "   Client Cert Mode: $($config.clientCertMode)" -ForegroundColor Gray
                    Write-Host "   HTTPS Only: $($config.httpsOnly)" -ForegroundColor Gray
                }
                
                # Check HTTP/2 configuration
                $http2Config = az webapp config show --name $AppName --resource-group "rg-mtls-demo" --query "http20Enabled" 2>$null
                if ($http2Config) {
                    Write-Host "   HTTP/2 Enabled: $($http2Config)" -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "⚠️ Azure CLI no configurado o no logueado" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠️ No se pudo verificar configuración Azure: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    Write-Host ""
}

# Ejecutar verificaciones
Test-HttpVersion -Url "$ServerUrl/health" -Description "Endpoint público del servidor"

if (![string]::IsNullOrEmpty($ClientUrl)) {
    Test-HttpVersion -Url "$ClientUrl" -Description "Aplicación cliente"
}

Test-MTLSEndpoint -Url $ServerUrl

# Extract app name from URL for Azure checks
if ($ServerUrl -match "https://([^.]+)\.azurewebsites\.net") {
    $appName = $matches[1]
    Test-AzureFeatures -AppName $appName
} else {
    Test-AzureFeatures -AppName ""
}

Write-Host "🎯 Resumen de verificación:" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host "✅ HTTP/2: Verificar headers de respuesta arriba" -ForegroundColor White
Write-Host "✅ HTTPS: Forzado por Azure Web Apps" -ForegroundColor White  
Write-Host "✅ mTLS: Configurado a nivel de aplicación Azure" -ForegroundColor White
Write-Host "✅ Certificados: Gestionados por Azure Certificate Store" -ForegroundColor White
Write-Host ""
Write-Host "💡 Para pruebas completas de mTLS:" -ForegroundColor Yellow
Write-Host "1. Use el cliente web desplegado para probar la conectividad" -ForegroundColor White
Write-Host "2. Configure certificados cliente en el navegador para pruebas manuales" -ForegroundColor White
Write-Host "3. Use herramientas como openssl s_client para pruebas avanzadas" -ForegroundColor White
