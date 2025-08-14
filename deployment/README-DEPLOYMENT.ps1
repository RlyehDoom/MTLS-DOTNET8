# Script de resumen del flujo de deployment mTLS
Write-Host "📋 RESUMEN DEL FLUJO DE DEPLOYMENT mTLS" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

Write-Host "🎯 CONFIGURACIÓN POR DEFECTO:" -ForegroundColor Cyan
Write-Host "• Resource Group: rg-mtls-demo" -ForegroundColor White
Write-Host "• Server App: mtls-server" -ForegroundColor White
Write-Host "• Client App: mtls-client" -ForegroundColor White
Write-Host "• Server Thumbprint: A37AB3C30590D3944F48438DC4E40A475C561F02" -ForegroundColor White
Write-Host "• Client Thumbprint: 7C63CEC64CB152CB0E06BF058C91506830A5568F" -ForegroundColor White
Write-Host ""

Write-Host "🔐 CERTIFICADOS UTILIZADOS:" -ForegroundColor Cyan
Write-Host "• Server: src/mTLS.Server/Certs/dev-env.pfx" -ForegroundColor White
Write-Host "• Client: src/mTLS.Server/Certs/dev-env_client.pfx" -ForegroundColor White
Write-Host "• Password: Developer2077" -ForegroundColor White
Write-Host ""

Write-Host "🚀 PASOS DEL DEPLOYMENT:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1️⃣ CREAR RECURSOS AZURE" -ForegroundColor Yellow
Write-Host "   Script: deploy-azure.ps1" -ForegroundColor Gray
Write-Host "   • Crea Resource Group" -ForegroundColor White
Write-Host "   • Crea App Service Plan (S1)" -ForegroundColor White
Write-Host "   • Crea Web Apps para Server y Client" -ForegroundColor White
Write-Host "   • Configura HTTPS y HTTP/2" -ForegroundColor White
Write-Host ""

Write-Host "2️⃣ SUBIR CERTIFICADOS" -ForegroundColor Yellow
Write-Host "   Script: upload-local-certificates.ps1" -ForegroundColor Gray
Write-Host "   • Sube certificados locales a Azure" -ForegroundColor White
Write-Host "   • Extrae thumbprints automáticamente" -ForegroundColor White
Write-Host "   • Configura app settings con thumbprints" -ForegroundColor White
Write-Host ""

Write-Host "3️⃣ DEPLOY APLICACIÓN SERVIDOR" -ForegroundColor Yellow
Write-Host "   Script: deploy-server.ps1" -ForegroundColor Gray
Write-Host "   • Build del proyecto mTLS.Server" -ForegroundColor White
Write-Host "   • Publica en modo Release" -ForegroundColor White
Write-Host "   • Crea ZIP de deployment" -ForegroundColor White
Write-Host "   • Deploy a Azure Web App" -ForegroundColor White
Write-Host ""

Write-Host "4️⃣ DEPLOY APLICACIÓN CLIENTE" -ForegroundColor Yellow
Write-Host "   Script: deploy-client.ps1" -ForegroundColor Gray
Write-Host "   • Build del proyecto mTLS.Client" -ForegroundColor White
Write-Host "   • Publica en modo Release" -ForegroundColor White
Write-Host "   • Crea ZIP de deployment" -ForegroundColor White
Write-Host "   • Deploy a Azure Web App" -ForegroundColor White
Write-Host ""

Write-Host "🌐 ENDPOINTS RESULTANTES:" -ForegroundColor Cyan
Write-Host "• Server: https://mtls-server.azurewebsites.net" -ForegroundColor White
Write-Host "  - /health (público)" -ForegroundColor Gray
Write-Host "  - /mtls-test (requiere certificado cliente)" -ForegroundColor Gray
Write-Host "  - /weatherforecast (público)" -ForegroundColor Gray
Write-Host ""
Write-Host "• Client: https://mtls-client.azurewebsites.net" -ForegroundColor White
Write-Host "  - / (info)" -ForegroundColor Gray
Write-Host "  - /test-server (prueba mTLS)" -ForegroundColor Gray
Write-Host "  - /cert-info (info certificado)" -ForegroundColor Gray
Write-Host ""

Write-Host "⚡ COMANDOS PARA EJECUTAR:" -ForegroundColor Green
Write-Host ""
Write-Host "Deployment completo automático:" -ForegroundColor Yellow
Write-Host "   .\deploy-complete.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "Deployment paso a paso:" -ForegroundColor Yellow
Write-Host "   .\deploy-azure.ps1" -ForegroundColor Cyan
Write-Host "   .\upload-local-certificates.ps1" -ForegroundColor Cyan
Write-Host "   .\deploy-server.ps1" -ForegroundColor Cyan
Write-Host "   .\deploy-client.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verificar flujo (sin deployar):" -ForegroundColor Yellow
Write-Host "   .\verify-deployment-flow.ps1" -ForegroundColor Cyan
Write-Host ""

Write-Host "✅ TODO LISTO PARA DEPLOYMENT A AZURE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
