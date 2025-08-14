# Build and Test Script for mTLS Projects

Write-Host "🔨 Building mTLS Solution..." -ForegroundColor Green

# Build shared library
Write-Host "Building Shared library..." -ForegroundColor Yellow
Set-Location "src/mTLS.Shared"
dotnet build
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to build Shared library"; exit 1 }

# Build server
Write-Host "Building Server..." -ForegroundColor Yellow
Set-Location "../mTLS.Server"
dotnet build
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to build Server"; exit 1 }

# Build client
Write-Host "Building Client..." -ForegroundColor Yellow
Set-Location "../mTLS.Client"
dotnet build
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to build Client"; exit 1 }

Set-Location "../.."

Write-Host "✅ All projects built successfully!" -ForegroundColor Green

Write-Host ""
Write-Host "🚀 To run locally:" -ForegroundColor Cyan
Write-Host "Terminal 1: cd src/mTLS.Server && dotnet run" -ForegroundColor White
Write-Host "Terminal 2: cd src/mTLS.Client && dotnet run --urls='https://localhost:5000'" -ForegroundColor White
Write-Host ""
Write-Host "🌐 URLs:" -ForegroundColor Cyan
Write-Host "Server: https://localhost:5001" -ForegroundColor White
Write-Host "Client: https://localhost:5000" -ForegroundColor White
