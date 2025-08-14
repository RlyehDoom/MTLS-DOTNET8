# Complete deployment script - creates Azure resources and deploys both applications
param(
    [string]$ResourceGroup = "rg-mtls-demo",
    [string]$Location = "East US",
    [string]$ServerCertThumbprint = "A37AB3C30590D3944F48438DC4E40A475C561F02",
    [string]$CACertThumbprint = "",
    [string]$ClientCertThumbprint = "7C63CEC64CB152CB0E06BF058C91506830A5568F"
)

# Determinar ruta base del script
$ScriptDir = $PSScriptRoot

Write-Host "🚀 Complete mTLS deployment to Azure..." -ForegroundColor Green
Write-Host "Script Directory: $ScriptDir" -ForegroundColor Gray

# Step 1: Create Azure resources
Write-Host "Step 1: Creating Azure resources..." -ForegroundColor Yellow
$DeployAzureScript = Join-Path $ScriptDir "deploy-azure.ps1"
& $DeployAzureScript -ResourceGroup $ResourceGroup -Location $Location -ServerCertThumbprint $ServerCertThumbprint -CACertThumbprint $CACertThumbprint -ClientCertThumbprint $ClientCertThumbprint

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create Azure resources"
    exit 1
}

# Step 2: Upload local certificates to Azure
Write-Host "Step 2: Uploading certificates to Azure..." -ForegroundColor Yellow
$UploadCertsScript = Join-Path $ScriptDir "upload-local-certificates.ps1"
& $UploadCertsScript -ResourceGroup $ResourceGroup -ServerAppName $ServerAppName -ClientAppName $ClientAppName

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to upload certificates"
    exit 1
}

# Step 3: Deploy server application
Write-Host "Step 3: Deploying server application..." -ForegroundColor Yellow
$DeployServerScript = Join-Path $ScriptDir "deploy-server.ps1"
& $DeployServerScript -ResourceGroup $ResourceGroup

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to deploy server application"
    exit 1
}

# Step 4: Deploy client application
Write-Host "Step 4: Deploying client application..." -ForegroundColor Yellow
$DeployClientScript = Join-Path $ScriptDir "deploy-client.ps1"
& $DeployClientScript -ResourceGroup $ResourceGroup

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to deploy client application"
    exit 1
}

Write-Host "🎉 Complete deployment finished successfully!" -ForegroundColor Green

$DeploymentInfoPath = Join-Path $ScriptDir "deployment-info.json"
if (Test-Path $DeploymentInfoPath) {
    $deploymentInfo = Get-Content $DeploymentInfoPath | ConvertFrom-Json
    Write-Host ""
    Write-Host "📋 Deployment Summary:" -ForegroundColor Cyan
    Write-Host "Resource Group: $($deploymentInfo.ResourceGroup)" -ForegroundColor White
    Write-Host "Server URL: $($deploymentInfo.ServerUrl)" -ForegroundColor White
    Write-Host "Client URL: $($deploymentInfo.ClientUrl)" -ForegroundColor White
    Write-Host ""
    Write-Host "🧪 Test the deployment:" -ForegroundColor Yellow
    Write-Host "1. Visit the client URL to test the mTLS connection"
    Write-Host "2. Use the /test-server endpoint to verify connectivity"
    Write-Host "3. Check the /cert-info endpoint to verify certificate loading"
}
