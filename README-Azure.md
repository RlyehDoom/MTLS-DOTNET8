# Manual Azure Portal Configuration for mTLS Demo

This guide provides step-by-step instructions for manually configuring the mTLS demo application in Azure Portal, including all the settings that are normally automated by the deployment scripts.

## 📋 Prerequisites

- Azure subscription with appropriate permissions
- X.509 certificates in PFX format:
  - Server certificate (`dev-env.pfx`)
  - Client certificate (`dev-env_client.pfx`)
  - CA certificate (`ca.crt`)
- Certificate passwords

## 🌐 Step 1: Create Resource Group

1. **Navigate to Azure Portal** (https://portal.azure.com)
2. **Click "Resource groups"** in the left sidebar
3. **Click "+ Create"**
4. **Configure Resource Group**:
   - **Subscription**: Select your subscription
   - **Resource group name**: `rg-mtls-demo`
   - **Region**: `Central US` (or your preferred region)
5. **Click "Review + create"** then **"Create"**

## 🚀 Step 2: Create App Service Plan

1. **Search for "App Service plans"** in the top search bar
2. **Click "+ Create"**
3. **Configure App Service Plan**:
   - **Subscription**: Select your subscription
   - **Resource Group**: Select `rg-mtls-demo`
   - **Name**: `asp-mtls-demo`
   - **Operating System**: `Linux`
   - **Region**: Same as resource group
   - **Pricing Tier**: `Basic B1` (or higher)
4. **Click "Review + create"** then **"Create"**

## 🖥️ Step 3: Create App Services

### Create Server App Service

1. **Search for "App Services"** in the top search bar
2. **Click "+ Create"**
3. **Configure Web App**:
   - **Subscription**: Select your subscription
   - **Resource Group**: `rg-mtls-demo`
   - **Name**: `mtls-server-[unique-suffix]` (e.g., `mtls-server-529349d5`)
   - **Publish**: `Code`
   - **Runtime stack**: `.NET 8 (LTS)`
   - **Operating System**: `Linux`
   - **Region**: Same as resource group
   - **App Service Plan**: Select `asp-mtls-demo`
4. **Click "Review + create"** then **"Create"**

### Create Client App Service

1. **Repeat the same steps** for the client:
   - **Name**: `mtls-client-[unique-suffix]` (e.g., `mtls-client-529349d5`)
   - **All other settings**: Same as server

## 🔐 Step 4: Upload SSL Certificates

### Upload Server Certificate

1. **Navigate to your Server App Service** (`mtls-server-[suffix]`)
2. **Go to "TLS/SSL settings"** in the left sidebar
3. **Click on "Private Key Certificates (.pfx)"** tab
4. **Click "+ Upload certificate"**
5. **Configure Certificate**:
   - **PFX certificate file**: Upload `dev-env.pfx`
   - **Certificate password**: Enter certificate password
   - **Certificate name**: `server-certificate`
6. **Click "Upload"**
7. **Copy the thumbprint** for later use

### Upload Client Certificate to Both App Services

1. **Repeat the certificate upload process** for both Server and Client App Services:
   - **Upload `dev-env_client.pfx`** with name `client-certificate`
   - **Upload CA certificate** if available as PFX
2. **Note all thumbprints** for configuration

## ⚙️ Step 5: Configure Application Settings

### Server App Service Configuration

1. **Navigate to your Server App Service**
2. **Go to "Configuration"** in the left sidebar
3. **Click on "Application settings"** tab
4. **Add the following settings** (click "+ New application setting" for each):

   ```
   ASPNETCORE_ENVIRONMENT = Production
   WEBSITE_LOAD_CERTIFICATES = *
   ```

5. **Add Certificate Configuration**:
   ```
   AzureCertificates__ServerCertThumbprint = [SERVER_CERT_THUMBPRINT]
   AzureCertificates__CACertThumbprint = [CA_CERT_THUMBPRINT]
   AzureCertificates__ClientCertThumbprint = [CLIENT_CERT_THUMBPRINT]
   ```

6. **Add Fallback Certificate Configuration**:
   ```
   Certificates__ServerCert = Certs/dev-env.pfx
   Certificates__ServerCertPassword = [PASSWORD]
   Certificates__CACert = Certs/ca.crt
   Certificates__ClientCert = Certs/dev-env_client.pfx
   Certificates__ClientCertPassword = [PASSWORD]
   ```

7. **Click "Save"**

### Client App Service Configuration

1. **Navigate to your Client App Service**
2. **Go to "Configuration"** in the left sidebar
3. **Add the following settings**:

   ```
   ASPNETCORE_ENVIRONMENT = Production
   WEBSITE_LOAD_CERTIFICATES = *
   ServerUrl = https://mtls-server-[suffix].azurewebsites.net
   ```

4. **Add Certificate Configuration** (same as server):
   ```
   AzureCertificates__ServerCertThumbprint = [SERVER_CERT_THUMBPRINT]
   AzureCertificates__CACertThumbprint = [CA_CERT_THUMBPRINT]
   AzureCertificates__ClientCertThumbprint = [CLIENT_CERT_THUMBPRINT]
   
   Certificates__ServerCert = Certs/dev-env.pfx
   Certificates__ServerCertPassword = [PASSWORD]
   Certificates__CACert = Certs/ca.crt
   Certificates__ClientCert = Certs/dev-env_client.pfx
   Certificates__ClientCertPassword = [PASSWORD]
   ```

5. **Click "Save"**

## 🔒 Step 6: Configure Client Certificate Authentication

### Server App Service - Enable Client Certificates

1. **Navigate to your Server App Service**
2. **Go to "TLS/SSL settings"**
3. **Click on "Protocol settings"** tab
4. **Configure Client Certificate Settings**:
   - **HTTPS Only**: `On`
   - **Minimum TLS Version**: `1.2`
   - **Client certificates**: `Allow` (not Require - we handle validation in code)
5. **Click "Save"**

### Alternative: Use Azure CLI for Client Certificate Mode

If the portal doesn't show client certificate options, use Azure CLI:

```bash
# Enable client certificates for server
az webapp update \
  --resource-group rg-mtls-demo \
  --name mtls-server-[suffix] \
  --client-cert-mode Optional

# Enable HTTPS only
az webapp update \
  --resource-group rg-mtls-demo \
  --name mtls-server-[suffix] \
  --https-only true
```

## 📦 Step 7: Deploy Applications

### Option 1: Using Azure Portal (Deployment Center)

1. **Navigate to App Service**
2. **Go to "Deployment Center"**
3. **Choose deployment source** (GitHub, Azure DevOps, etc.)
4. **Configure build and deployment pipeline**

### Option 2: Using ZIP Deploy via Portal

1. **Build your application locally**:
   ```bash
   cd src/mTLS.Server
   dotnet publish -c Release -o publish
   ```

2. **Create ZIP package**:
   ```bash
   cd publish
   zip -r ../server-deploy.zip .
   ```

3. **Upload via Kudu**:
   - Navigate to `https://mtls-server-[suffix].scm.azurewebsites.net`
   - Go to "Tools" > "Zip Push Deploy"
   - Drag and drop your ZIP file

### Option 3: Using Azure CLI

```bash
# Deploy server
az webapp deployment source config-zip \
  --resource-group rg-mtls-demo \
  --name mtls-server-[suffix] \
  --src server-deploy.zip

# Deploy client
az webapp deployment source config-zip \
  --resource-group rg-mtls-demo \
  --name mtls-client-[suffix] \
  --src client-deploy.zip
```

## 🔧 Step 8: Configure Custom Domains (Optional)

### Add Custom Domain

1. **Navigate to App Service**
2. **Go to "Custom domains"**
3. **Click "+ Add custom domain"**
4. **Enter your domain** and follow validation steps
5. **Bind SSL certificate** once domain is validated

### Configure DNS

Add CNAME records pointing to your App Service:
```
server.yourdomain.com -> mtls-server-[suffix].azurewebsites.net
client.yourdomain.com -> mtls-client-[suffix].azurewebsites.net
```

## 📊 Step 9: Configure Monitoring and Logging

### Application Insights

1. **Navigate to App Service**
2. **Go to "Application Insights"**
3. **Click "Turn on Application Insights"**
4. **Create new resource** or select existing one
5. **Click "Apply"**

### Diagnostic Logs

1. **Go to "App Service logs"**
2. **Configure logging**:
   - **Application Logging**: `File System` (Verbose)
   - **Web server logging**: `File System`
   - **Detailed error messages**: `On`
   - **Failed request tracing**: `On`
3. **Click "Save"**

## 🚦 Step 10: Health Checks and Scaling

### Configure Health Check

1. **Go to "Health check"** in App Service
2. **Enable health check**:
   - **Path**: `/health`
   - **Load balancing**: `Least Requests`
3. **Click "Save"**

### Configure Auto-scaling

1. **Go to App Service Plan**
2. **Go to "Scale out (App Service plan)"**
3. **Configure rules** based on CPU, memory, or custom metrics

## 🔍 Step 11: Testing and Verification

### Test Endpoints

1. **Server Health Check**:
   ```
   https://mtls-server-[suffix].azurewebsites.net/health
   ```

2. **Client Health Check**:
   ```
   https://mtls-client-[suffix].azurewebsites.net/cert-info
   ```

3. **mTLS Test**:
   ```
   https://mtls-client-[suffix].azurewebsites.net/test-server
   ```

### Monitor Logs

1. **Go to "Log stream"** in App Service to see real-time logs
2. **Check "Diagnose and solve problems"** for issues
3. **Review Application Insights** for performance metrics

## 🛠️ Troubleshooting

### Common Issues

1. **Certificate Not Loading**:
   - Verify `WEBSITE_LOAD_CERTIFICATES = *` is set
   - Check certificate thumbprints match uploaded certificates
   - Ensure certificates are uploaded to both App Services

2. **Client Certificate Not Forwarded**:
   - Verify client certificate mode is set to `Optional` or `Required`
   - Check X-ARR-ClientCert header in debug endpoints

3. **Application Startup Issues**:
   - Check Application Logs in portal
   - Verify all required configuration settings
   - Ensure certificate passwords are correct

### Debug Endpoints

Use these endpoints for troubleshooting:

- `/cert-info` - Shows certificate loading status
- `/debug-headers` - Shows all HTTP headers received
- `/health` - Basic health check

### Log Locations

- **Application Logs**: `/home/LogFiles/Application/`
- **Web Server Logs**: `/home/LogFiles/http/`
- **Deployment Logs**: Available in Deployment Center

## 📝 Security Considerations

1. **Certificate Storage**: Consider using Azure Key Vault for production
2. **Access Control**: Configure appropriate RBAC permissions
3. **Network Security**: Consider using VNets and private endpoints
4. **Monitoring**: Set up alerts for certificate expiration
5. **Backup**: Regularly backup certificates and configuration

## 🔄 Maintenance Tasks

### Regular Maintenance

1. **Certificate Renewal**: Monitor certificate expiration dates
2. **Security Updates**: Keep runtime versions updated
3. **Log Management**: Configure log retention policies
4. **Performance Monitoring**: Review Application Insights metrics
5. **Backup Configuration**: Export ARM templates for disaster recovery

### Scaling Considerations

- Monitor resource usage and scale App Service Plan as needed
- Consider using Azure Front Door for global load balancing
- Implement caching strategies for better performance
- Use Azure CDN for static content delivery

---

## 📚 Additional Resources

- [Azure App Service Documentation](https://docs.microsoft.com/en-us/azure/app-service/)
- [TLS/SSL Certificates in Azure](https://docs.microsoft.com/en-us/azure/app-service/configure-ssl-certificate)
- [Azure App Service Security](https://docs.microsoft.com/en-us/azure/app-service/overview-security)
- [Application Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)