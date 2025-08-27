# mTLS Demo Application

A complete mutual TLS (mTLS) demonstration application built with ASP.NET Core, featuring both server and client components with certificate-based authentication.

## 📋 Overview

This project demonstrates:
- **Mutual TLS Authentication**: Both client and server authenticate using X.509 certificates
- **Azure App Service Deployment**: Production-ready deployment to Azure with certificate management
- **Development & Production Modes**: Different configurations for local development and Azure deployment
- **Certificate Management**: Support for both local PFX certificates and Azure Key Vault integration

## 🏗️ Architecture

- **mTLS.Server**: API server that validates client certificates and serves protected endpoints
- **mTLS.Client**: Client application that connects to the server using client certificates
- **mTLS.Shared**: Common models and certificate services shared between server and client

## 🚀 Running Locally

### Prerequisites

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- Valid X.509 certificates (PFX format) for testing

### Development Setup

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd mTLS
   ```

2. **Configure certificates** (place in `src/mTLS.Server/Certs/` and `src/mTLS.Client/Certs/`):
   - `dev-env.pfx` - Server certificate
   - `dev-env_client.pfx` - Client certificate
   - `ca.crt` - Certificate Authority certificate

3. **Update appsettings.Development.json** in both projects with your certificate passwords:
   ```json
   {
     "Certificates": {
       "ServerCert": "Certs/dev-env.pfx",
       "ServerCertPassword": "your-password",
       "CACert": "Certs/ca.crt",
       "ClientCert": "Certs/dev-env_client.pfx",
       "ClientCertPassword": "your-password"
     }
   }
   ```

### Running the Applications

#### Option 1: Using Visual Studio / Visual Studio Code
- Open the solution file or individual projects
- Set multiple startup projects (both Server and Client)
- Press F5 to run

#### Option 2: Using dotnet CLI

1. **Start the Server**:
   ```bash
   cd src/mTLS.Server
   dotnet run
   ```
   Server will start on:
   - HTTP: `http://localhost:5000`
   - HTTPS: `https://localhost:5001`

2. **Start the Client** (in a new terminal):
   ```bash
   cd src/mTLS.Client
   dotnet run
   ```
   Client will start on:
   - HTTP: `http://localhost:5002`
   - HTTPS: `https://localhost:5003`

### Testing the mTLS Connection

1. **Access the Client UI**: Navigate to `https://localhost:5003`
2. **Test mTLS**: Visit `https://localhost:5003/test-server` to test the mTLS connection
3. **View Certificate Info**: Check `https://localhost:5003/cert-info` for certificate details

### Available Endpoints

#### Server Endpoints
- `GET /` - Static index page
- `GET /health` - Health check (public)
- `GET /cert-info` - Certificate information (public)
- `GET /weatherforecast` - Sample API endpoint (public)
- `GET /mtls-test` - mTLS protected endpoint (requires client certificate)

#### Client Endpoints
- `GET /` - Static index page
- `GET /cert-info` - Client certificate information
- `GET /test-server` - Test mTLS connection to server

## 🌐 Azure Deployment

### Prerequisites

- Azure subscription
- Azure CLI installed and logged in
- WSL (Windows Subsystem for Linux) or Linux environment
- Required tools: `zip`, `7z`, or PowerShell

### WSL Setup (Windows Users)

1. **Install WSL** (if not already installed):
   ```bash
   wsl --install
   ```

2. **Install required tools in WSL**:
   ```bash
   sudo apt update
   sudo apt install zip unzip curl
   ```

3. **Install Azure CLI in WSL**:
   ```bash
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   ```

4. **Login to Azure**:
   ```bash
   az login
   ```

### Deployment Scripts

The project includes automated deployment scripts in the `deployment/` folder:

#### 1. Create Azure Resources
```bash
cd deployment
./01-create-resources.sh
```
Creates:
- Resource Group
- App Service Plan
- Two App Services (server and client)
- Generates unique names to avoid conflicts

#### 2. Configure mTLS
```bash
./02-configure-mtls.sh
```
Configures:
- Certificate settings in Azure
- Client certificate requirements
- Application settings for mTLS

#### 3. Deploy Server
```bash
./03-deploy-server.sh
```
- Builds and publishes the server project
- Creates deployment package
- Deploys to Azure App Service
- Verifies deployment

#### 4. Deploy Client
```bash
./04-deploy-client.sh
```
- Builds and publishes the client project
- Creates deployment package
- Deploys to Azure App Service
- Verifies deployment

#### 5. Verify Deployment
```bash
./05-verify-deployment.sh
```
- Tests all endpoints
- Verifies mTLS functionality
- Provides deployment summary

### Manual Certificate Upload

After running the scripts, you need to upload your certificates to Azure:

1. **Upload Server Certificate**:
   ```bash
   az webapp config ssl upload \
     --resource-group <resource-group> \
     --name <server-app-name> \
     --certificate-file path/to/server-cert.pfx \
     --certificate-password <password>
   ```

2. **Upload Client Certificate**:
   ```bash
   az webapp config ssl upload \
     --resource-group <resource-group> \
     --name <client-app-name> \
     --certificate-file path/to/client-cert.pfx \
     --certificate-password <password>
   ```

3. **Update configuration** with the actual certificate thumbprints from Azure

### Environment-Specific Configuration

The application automatically detects the environment:

- **Development**: Uses certificates from `Certs/` folder and `wwwroot/` for static files
- **Production** (Azure): Uses Azure-managed certificates and serves static files from root

## 🛠️ Troubleshooting

### Common Issues

1. **Certificate Not Found**: Ensure certificates are in the correct location and passwords are correct
2. **Port Conflicts**: Check if ports 5000-5003 are available
3. **Certificate Validation Errors**: Verify certificate chain and trust relationships

### Debugging

- Check application logs in Azure App Service
- Use `/cert-info` endpoints to verify certificate loading
- Test with `/debug-headers` endpoint to see what headers are received

## 📁 Project Structure

```
mTLS/
├── src/
│   ├── mTLS.Server/          # API Server
│   ├── mTLS.Client/          # Client Application  
│   └── mTLS.Shared/          # Shared Components
├── deployment/               # Azure deployment scripts
│   ├── 01-create-resources.sh
│   ├── 02-configure-mtls.sh
│   ├── 03-deploy-server.sh
│   ├── 04-deploy-client.sh
│   └── 05-verify-deployment.sh
└── README.md
```

## 🔒 Security Considerations

- Certificates should be stored securely (Azure Key Vault in production)
- Use strong passwords for certificate files
- Regularly rotate certificates
- Monitor certificate expiration dates
- Implement proper certificate validation in production

## 📝 License

This project is for demonstration purposes. Please review and adjust security settings before using in production environments.