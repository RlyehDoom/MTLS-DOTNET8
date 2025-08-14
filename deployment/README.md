# mTLS Azure Deployment Guide

Este proyecto ha sido segregado en componentes para facilitar el despliegue en Azure WebSites con configuración mTLS.

## 🏗️ Estructura del Proyecto

```
src/
├── mTLS.Shared/           # Componentes transversales
│   ├── Models/            # Modelos compartidos
│   └── Services/          # Servicios de certificados
├── mTLS.Server/           # Aplicación servidor
│   ├── Program.cs         # API mTLS
│   └── appsettings.json   # Configuración local
└── mTLS.Client/           # Aplicación cliente
    ├── Program.cs         # Cliente de prueba
    └── appsettings.json   # Configuración local

deployment/
├── deploy-azure.ps1       # Crear recursos Azure
├── deploy-server.ps1      # Desplegar servidor
├── deploy-client.ps1      # Desplegar cliente
└── deploy-complete.ps1    # Despliegue completo
```

## 🚀 Despliegue Local

### Prerrequisitos
- .NET 8 SDK
- Certificados en carpetas `Certs/` de cada proyecto

### Ejecutar localmente
```powershell
# Servidor (puerto 5001)
cd src/mTLS.Server
dotnet run

# Cliente (puerto 5000)
cd src/mTLS.Client
dotnet run --urls="https://localhost:5000"
```

## ☁️ Despliegue en Azure

### Prerrequisitos
- Azure CLI instalado y configurado
- Certificados subidos a Azure App Service Certificate Store
- Thumbprints de los certificados

### Características Azure configuradas
- **HTTP/2**: Habilitado automáticamente
- **mTLS**: Configurado con `clientCertEnabled=true` y `clientCertMode=Required`
- **HTTPS**: Forzado en todos los endpoints
- **Forwarded Headers**: Configurado para Azure Load Balancer
- **Security Headers**: HSTS, X-Frame-Options, etc.

### Despliegue completo
```powershell
cd deployment
.\deploy-complete.ps1 -ServerCertThumbprint "ABC123..." -CACertThumbprint "DEF456..." -ClientCertThumbprint "GHI789..."
```

### Despliegue por pasos
```powershell
# 1. Crear recursos Azure
.\deploy-azure.ps1 -ServerCertThumbprint "ABC123..." -CACertThumbprint "DEF456..." -ClientCertThumbprint "GHI789..."

# 2. Desplegar servidor
.\deploy-server.ps1

# 3. Desplegar cliente
.\deploy-client.ps1
```

## 🔧 Configuración de Certificados en Azure

### Opción 1: App Service Certificates
```powershell
# Subir certificado al App Service
az webapp config ssl upload \
    --resource-group rg-mtls-demo \
    --name your-app-name \
    --certificate-file path/to/cert.pfx \
    --certificate-password "your-password"
```

### Opción 2: Azure Key Vault
```powershell
# Crear Key Vault
az keyvault create --name your-keyvault --resource-group rg-mtls-demo --location "East US"

# Subir certificado
az keyvault certificate import \
    --vault-name your-keyvault \
    --name server-cert \
    --file path/to/cert.pfx \
    --password "your-password"
```

## 🧪 Verificación de Despliegue

### Script de verificación automática
```powershell
# Verificar HTTP/2 y mTLS después del despliegue
.\verify-azure-deployment.ps1
```

### Verificación manual
```bash
# Verificar HTTP/2
curl -I --http2 https://your-app.azurewebsites.net/health

# Verificar headers de seguridad
curl -I https://your-app.azurewebsites.net/health

# Probar endpoint mTLS (debería fallar sin certificado)
curl https://your-app.azurewebsites.net/mtls-test
```
- `GET /health` - Endpoint público
- `GET /weatherforecast` - Endpoint público
- `GET /mtls-test` - Endpoint protegido con mTLS

### Endpoints del Cliente
- `GET /` - Información del cliente
- `GET /test-server` - Probar conexión mTLS con el servidor
- `GET /cert-info` - Información del certificado cliente

## 🔒 Características de Seguridad

### Configuración Local
- Certificados cargados desde archivos PFX
- Validación personalizada de cadena de certificados
- Soporte para desarrollo con certificados auto-firmados

### Configuración Azure
- Certificados cargados desde Azure Certificate Store
- Validación automática por thumbprint
- HTTPS obligatorio en todos los endpoints
- Configuración específica por entorno

## 🏷️ Variables de Entorno Azure

### Servidor
```
ASPNETCORE_ENVIRONMENT=Production
AzureCertificates__ServerCertThumbprint=ABC123...
AzureCertificates__CACertThumbprint=DEF456...
AzureCertificates__ClientCertThumbprint=GHI789...
```

### Cliente
```
ASPNETCORE_ENVIRONMENT=Production
ServerUrl=https://your-server.azurewebsites.net
AzureCertificates__ClientCertThumbprint=GHI789...
```

## 📋 Checklist de Despliegue

- [ ] Certificados subidos a Azure
- [ ] Thumbprints configurados correctamente
- [ ] Apps creadas en Azure
- [ ] Configuración HTTPS habilitada
- [ ] Variables de entorno configuradas
- [ ] Aplicaciones desplegadas
- [ ] Pruebas de conectividad realizadas

## 🐛 Solución de Problemas

### Certificado no encontrado
- Verificar thumbprints en configuración
- Asegurar que certificados estén en Certificate Store

### Error de conexión mTLS
- Verificar URL del servidor en cliente
- Comprobar configuración de autenticación
- Revisar logs de Azure App Service

### Error de validación SSL
- Confirmar que certificados estén firmados por CA válida
- Verificar configuración de dominio personalizado
