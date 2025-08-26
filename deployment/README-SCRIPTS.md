# mTLS Azure Deployment Scripts

Este conjunto de scripts permite desplegar de manera automatizada y configurable el POC de mTLS Server y Client en Azure usando Azure CLI.

## 📁 Scripts Disponibles

### 1. `01-create-azure-resources.sh`
**Propósito**: Crear todos los recursos de Azure necesarios para el despliegue.

**Funcionalidades**:
- Crear Resource Group
- Crear App Service Plan
- Crear Web Apps para Server y Client  
- Habilitar HTTPS only
- Habilitar HTTP/2
- Guardar información de despliegue

**Variables de entorno**:
```bash
export RESOURCE_GROUP="rg-mtls-demo"
export LOCATION="eastus"
export APP_SERVICE_PLAN="asp-mtls-demo"
export SERVER_APP_NAME="mtls-server-$(date +%s)"
export CLIENT_APP_NAME="mtls-client-$(date +%s)"
export SKU="S1"
```

**Uso**:
```bash
./01-create-azure-resources.sh
```

### 2. `02-configure-mtls.sh`
**Propósito**: Configurar las aplicaciones con las settings de mTLS.

**Funcionalidades**:
- Configurar app settings del servidor
- Configurar app settings del cliente
- Habilitar autenticación de certificado cliente
- Configurar comandos de inicio
- Actualizar información de despliegue

**Certificados requeridos**:
- Server Certificate Thumbprint
- CA Certificate Thumbprint  
- Client Certificate Thumbprint

**Uso**:
```bash
./02-configure-mtls.sh
# El script pedirá interactivamente los thumbprints de certificados
```

### 3. `03-deploy-server.sh`
**Propósito**: Compilar y desplegar la aplicación servidor.

**Funcionalidades**:
- Limpieza de builds anteriores
- Restaurar dependencias NuGet
- Compilar proyecto
- Publicar aplicación
- Crear paquete de despliegue
- Desplegar a Azure
- Verificar funcionamiento
- Limpiar archivos temporales

**Uso**:
```bash
./03-deploy-server.sh
```

### 4. `04-deploy-client.sh`
**Propósito**: Compilar y desplegar la aplicación cliente.

**Funcionalidades**:
- Similar al servidor pero para el cliente
- Verifica conectividad con el servidor
- Prueba endpoints básicos

**Uso**:
```bash
./04-deploy-client.sh
```

### 5. `05-verify-deployment.sh`
**Propósito**: Verificar completamente el despliegue y funcionalidad mTLS.

**Funcionalidades**:
- Verificar recursos de Azure
- Probar conectividad básica
- Verificar soporte HTTP/2
- Probar headers de seguridad
- Verificar configuración mTLS
- Probar comunicación end-to-end
- Revisar logs de aplicación
- Generar reporte de estado

**Uso**:
```bash
./05-verify-deployment.sh
```

### 6. `deploy-complete.sh`
**Propósito**: Orquestar el despliegue completo ejecutando todos los scripts en secuencia.

**Funcionalidades**:
- Ejecutar todos los pasos automáticamente
- Manejo de errores y continuación
- Modo interactivo y no-interactivo
- Posibilidad de saltar pasos específicos
- Reporte final de despliegue

**Opciones**:
```bash
# Despliegue completo interactivo
./deploy-complete.sh

# Despliegue no-interactivo
./deploy-complete.sh -y

# Saltar creación de recursos (si ya existen)
./deploy-complete.sh --skip-resources

# Saltar verificación
./deploy-complete.sh --skip-verify

# Ver ayuda
./deploy-complete.sh --help
```

## 🚀 Flujo de Despliegue Recomendado

### Despliegue Completo (Recomendado)
```bash
# Hacer ejecutables los scripts
chmod +x *.sh

# Ejecutar despliegue completo
./deploy-complete.sh
```

### Despliegue Manual Paso a Paso
```bash
# 1. Crear recursos Azure
./01-create-azure-resources.sh

# 2. Configurar mTLS (requiere thumbprints de certificados)
./02-configure-mtls.sh

# 3. Desplegar servidor
./03-deploy-server.sh

# 4. Desplegar cliente  
./04-deploy-client.sh

# 5. Verificar despliegue
./05-verify-deployment.sh
```

## 📋 Prerrequisitos

### Herramientas Requeridas
- **Azure CLI**: `az login` completado
- **jq**: Para procesamiento JSON
- **curl**: Para pruebas de conectividad
- **zip** o **tar**: Para crear paquetes
- **.NET 8 SDK**: Para compilar aplicaciones

### Certificados
Antes de ejecutar `02-configure-mtls.sh`, asegúrate de tener:
- Certificados subidos a Azure App Service Certificate Store
- Los thumbprints de:
  - Certificado del servidor
  - Certificado de la CA
  - Certificado del cliente

## 📊 Archivo `deployment-info.json`

Los scripts generan y mantienen un archivo `deployment-info.json` que contiene:

```json
{
  "ResourceGroup": "rg-mtls-demo",
  "Location": "eastus",
  "AppServicePlan": "asp-mtls-demo", 
  "ServerAppName": "mtls-server-1234567890",
  "ClientAppName": "mtls-client-1234567890",
  "ServerUrl": "https://mtls-server-1234567890.azurewebsites.net",
  "ClientUrl": "https://mtls-client-1234567890.azurewebsites.net",
  "ServerCertThumbprint": "ABC123...",
  "CACertThumbprint": "DEF456...",
  "ClientCertThumbprint": "GHI789...",
  "DeploymentStatus": "Completed",
  "ServerStatus": "Running",
  "ClientStatus": "Running",
  "Timestamp": "2025-01-15T10:30:00.000Z"
}
```

## 🔧 Personalización

### Variables de Entorno
Puedes personalizar el despliegue estableciendo variables de entorno:

```bash
# Ejemplo de personalización
export RESOURCE_GROUP="mi-grupo-mtls"
export LOCATION="centralus"
export SERVER_APP_NAME="mi-servidor-mtls"
export CLIENT_APP_NAME="mi-cliente-mtls"
export SKU="B1"

# Ejecutar despliegue con configuración personalizada
./deploy-complete.sh
```

### Certificados por Variables de Entorno
```bash
export SERVER_CERT_THUMBPRINT="tu-thumbprint-servidor"
export CA_CERT_THUMBPRINT="tu-thumbprint-ca"
export CLIENT_CERT_THUMBPRINT="tu-thumbprint-cliente"

# El script de configuración usará estos valores automáticamente
./02-configure-mtls.sh
```

## 🐛 Solución de Problemas

### Errores Comunes

1. **Azure CLI no logueado**:
   ```bash
   az login
   ```

2. **Scripts no ejecutables**:
   ```bash
   chmod +x *.sh
   ```

3. **jq no instalado**:
   ```bash
   # Ubuntu/Debian
   sudo apt-get install jq
   
   # macOS
   brew install jq
   
   # Windows (WSL)
   sudo apt-get install jq
   ```

4. **Certificados no encontrados**:
   - Verificar que los certificados estén subidos en Azure
   - Confirmar que los thumbprints sean correctos
   - Revisar permisos del App Service para acceder a certificados

### Verificación Manual

```bash
# Verificar estado de recursos
az webapp list --resource-group rg-mtls-demo --output table

# Verificar configuración de certificados  
az webapp show --resource-group rg-mtls-demo --name tu-app --query clientCertEnabled

# Probar endpoints
curl https://tu-servidor.azurewebsites.net/health
curl https://tu-cliente.azurewebsites.net/
```

## 📈 Monitoreo Post-Despliegue

Los scripts configuran automáticamente:
- HTTPS obligatorio
- HTTP/2 habilitado
- Headers de seguridad
- Autenticación de certificado cliente

Para monitoreo continuo, considera implementar:
- Azure Application Insights
- Azure Monitor alerts
- Health checks personalizados
- Log analytics

## 🔒 Consideraciones de Seguridad

- Los thumbprints de certificados se almacenan como app settings
- No se almacenan claves privadas en el código
- HTTPS es obligatorio para todas las comunicaciones
- Los certificados deben estar firmados por una CA válida para producción