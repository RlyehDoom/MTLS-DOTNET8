# Deploy Server Application to Azure
param(
    [string]$ResourceGroup = "rg-mtls-demo",
    [string]$ServerAppName = ""
)

# Determinar ruta base del script
$ScriptDir = $PSScriptRoot
$ProjectRoot = Split-Path $ScriptDir -Parent

# Ruta al archivo de información de deployment
$DeploymentInfoPath = Join-Path $ScriptDir "deployment-info.json"

if ([string]::IsNullOrEmpty($ServerAppName)) {
    if (Test-Path $DeploymentInfoPath) {
        $deploymentInfo = Get-Content $DeploymentInfoPath | ConvertFrom-Json
        $ServerAppName = $deploymentInfo.ServerAppName
        $ResourceGroup = $deploymentInfo.ResourceGroup
    } else {
        Write-Error "ServerAppName not provided and deployment-info.json not found"
        exit 1
    }
}

Write-Host "📦 Building and deploying Server application..." -ForegroundColor Green
Write-Host "Script Directory: $ScriptDir" -ForegroundColor Gray
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Gray

# Build the server project
Write-Host "🔨 Building server project..." -ForegroundColor Yellow
$ServerProjectPath = Join-Path $ProjectRoot "src\mTLS.Server"
Set-Location $ServerProjectPath
dotnet publish -c Release -o ./publish

# Create deployment package
Write-Host "📦 Creating deployment package..." -ForegroundColor Yellow
$DeploymentZipPath = Join-Path $ScriptDir "server-deployment.zip"
Compress-Archive -Path "./publish/*" -DestinationPath $DeploymentZipPath -Force

# Deploy to Azure
Write-Host "🚀 Deploying to Azure Web App: $ServerAppName" -ForegroundColor Yellow
Set-Location "../../deployment"
az webapp deployment source config-zip `
    --resource-group $ResourceGroup `
    --name $ServerAppName `
    --src "server-deployment.zip"

Write-Host "✅ Server deployment completed!" -ForegroundColor Green
Write-Host "🌐 Server URL: https://$ServerAppName.azurewebsites.net" -ForegroundColor Cyan

# Cleanup
Remove-Item "server-deployment.zip" -ErrorAction SilentlyContinue
