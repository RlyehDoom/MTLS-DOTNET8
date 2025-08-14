# Deploy Client Application to Azure
param(
    [string]$ResourceGroup = "rg-mtls-demo",
    [string]$ClientAppName = ""
)

# Determinar ruta base del script
$ScriptDir = $PSScriptRoot
$ProjectRoot = Split-Path $ScriptDir -Parent

# Ruta al archivo de información de deployment
$DeploymentInfoPath = Join-Path $ScriptDir "deployment-info.json"

if ([string]::IsNullOrEmpty($ClientAppName)) {
    if (Test-Path $DeploymentInfoPath) {
        $deploymentInfo = Get-Content $DeploymentInfoPath | ConvertFrom-Json
        $ClientAppName = $deploymentInfo.ClientAppName
        $ResourceGroup = $deploymentInfo.ResourceGroup
    } else {
        Write-Error "ClientAppName not provided and deployment-info.json not found"
        exit 1
    }
}

Write-Host "📦 Building and deploying Client application..." -ForegroundColor Green
Write-Host "Script Directory: $ScriptDir" -ForegroundColor Gray
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Gray

# Build the client project
Write-Host "🔨 Building client project..." -ForegroundColor Yellow
$ClientProjectPath = Join-Path $ProjectRoot "src\mTLS.Client"
Set-Location $ClientProjectPath
dotnet publish -c Release -o ./publish

# Create deployment package
Write-Host "📦 Creating deployment package..." -ForegroundColor Yellow
$DeploymentZipPath = Join-Path $ScriptDir "client-deployment.zip"
Compress-Archive -Path "./publish/*" -DestinationPath $DeploymentZipPath -Force

# Deploy to Azure
Write-Host "🚀 Deploying to Azure Web App: $ClientAppName" -ForegroundColor Yellow
Set-Location "../../deployment"
az webapp deployment source config-zip `
    --resource-group $ResourceGroup `
    --name $ClientAppName `
    --src "client-deployment.zip"

Write-Host "✅ Client deployment completed!" -ForegroundColor Green
Write-Host "🌐 Client URL: https://$ClientAppName.azurewebsites.net" -ForegroundColor Cyan

# Cleanup
Remove-Item "client-deployment.zip" -ErrorAction SilentlyContinue
