#!/bin/bash
# =============================================================================
# Script: 02-configure-mtls.sh
# Description: Configure mTLS settings for Azure Web Apps
# Prerequisites: Resources created with 01-create-azure-resources.sh
# =============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to load deployment info
load_deployment_info() {
    if [[ ! -f "deployment-info.json" ]]; then
        echo -e "${RED}❌ deployment-info.json not found. Please run 01-create-azure-resources.sh first.${NC}"
        exit 1
    fi
    
    RESOURCE_GROUP=$(cat deployment-info.json | jq -r '.ResourceGroup')
    SERVER_APP_NAME=$(cat deployment-info.json | jq -r '.ServerAppName')
    CLIENT_APP_NAME=$(cat deployment-info.json | jq -r '.ClientAppName')
    SERVER_URL=$(cat deployment-info.json | jq -r '.ServerUrl')
    
    echo -e "${BLUE}📋 Loaded deployment configuration:${NC}"
    echo -e "  Resource Group: ${CYAN}$RESOURCE_GROUP${NC}"
    echo -e "  Server App: ${CYAN}$SERVER_APP_NAME${NC}"
    echo -e "  Client App: ${CYAN}$CLIENT_APP_NAME${NC}"
    echo ""
}

# Function to get certificate thumbprints from user
get_certificate_thumbprints() {
    echo -e "${YELLOW}🔑 Certificate Configuration${NC}"
    echo -e "${BLUE}Please provide the certificate thumbprints:${NC}"
    echo ""
    
    # Server Certificate Thumbprint
    if [[ -z "$SERVER_CERT_THUMBPRINT" ]]; then
        read -p "Server Certificate Thumbprint: " SERVER_CERT_THUMBPRINT
    fi
    
    # CA Certificate Thumbprint
    if [[ -z "$CA_CERT_THUMBPRINT" ]]; then
        read -p "CA Certificate Thumbprint: " CA_CERT_THUMBPRINT
    fi
    
    # Client Certificate Thumbprint
    if [[ -z "$CLIENT_CERT_THUMBPRINT" ]]; then
        read -p "Client Certificate Thumbprint: " CLIENT_CERT_THUMBPRINT
    fi
    
    echo ""
    echo -e "${CYAN}Certificate Thumbprints:${NC}"
    echo -e "  Server: ${YELLOW}$SERVER_CERT_THUMBPRINT${NC}"
    echo -e "  CA: ${YELLOW}$CA_CERT_THUMBPRINT${NC}"
    echo -e "  Client: ${YELLOW}$CLIENT_CERT_THUMBPRINT${NC}"
    echo ""
}

# Function to configure server application settings
configure_server_settings() {
    echo -e "${YELLOW}⚙️  Configuring Server App Settings...${NC}"
    
    az webapp config appsettings set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SERVER_APP_NAME" \
        --settings \
            "ASPNETCORE_ENVIRONMENT=Production" \
            "ASPNETCORE_FORWARDEDHEADERS_ENABLED=true" \
            "ASPNETCORE_HTTPS_PORT=443" \
            "AzureCertificates__ServerCertThumbprint=$SERVER_CERT_THUMBPRINT" \
            "AzureCertificates__CACertThumbprint=$CA_CERT_THUMBPRINT" \
            "AzureCertificates__ClientCertThumbprint=$CLIENT_CERT_THUMBPRINT" \
        --output table
    
    echo -e "${GREEN}✅ Server app settings configured${NC}"
}

# Function to configure client application settings
configure_client_settings() {
    echo -e "${YELLOW}⚙️  Configuring Client App Settings...${NC}"
    
    az webapp config appsettings set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLIENT_APP_NAME" \
        --settings \
            "ASPNETCORE_ENVIRONMENT=Production" \
            "ASPNETCORE_FORWARDEDHEADERS_ENABLED=true" \
            "ASPNETCORE_HTTPS_PORT=443" \
            "ServerUrl=$SERVER_URL" \
            "AzureCertificates__ClientCertThumbprint=$CLIENT_CERT_THUMBPRINT" \
            "AzureCertificates__ServerCertThumbprint=$SERVER_CERT_THUMBPRINT" \
        --output table
    
    echo -e "${GREEN}✅ Client app settings configured${NC}"
}

# Function to enable client certificate authentication
enable_client_certificates() {
    echo -e "${YELLOW}🔒 Enabling client certificate authentication for server...${NC}"
    
    az webapp update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SERVER_APP_NAME" \
        --set clientCertEnabled=true \
        --set clientCertMode=Required \
        --output table
    
    echo -e "${GREEN}✅ Client certificate authentication enabled${NC}"
}

# Function to configure custom startup command
configure_startup_command() {
    echo -e "${YELLOW}🚀 Configuring startup commands...${NC}"
    
    # Server startup command
    az webapp config set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SERVER_APP_NAME" \
        --startup-file "dotnet mTLS.Server.dll" \
        --output none
    
    # Client startup command  
    az webapp config set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLIENT_APP_NAME" \
        --startup-file "dotnet mTLS.Client.dll" \
        --output none
    
    echo -e "${GREEN}✅ Startup commands configured${NC}"
}

# Function to configure connection strings (if needed)
configure_connection_strings() {
    echo -e "${YELLOW}🔗 Configuring connection strings (if needed)...${NC}"
    
    # Add any connection strings here if your application requires them
    # For now, this is a placeholder
    
    echo -e "${BLUE}ℹ️  No additional connection strings required${NC}"
}

# Function to update deployment info
update_deployment_info() {
    echo -e "${YELLOW}📄 Updating deployment information...${NC}"
    
    # Read existing deployment info
    DEPLOYMENT_INFO=$(cat deployment-info.json)
    
    # Update with certificate thumbprints and configuration status
    UPDATED_INFO=$(echo "$DEPLOYMENT_INFO" | jq \
        --arg server_cert "$SERVER_CERT_THUMBPRINT" \
        --arg ca_cert "$CA_CERT_THUMBPRINT" \
        --arg client_cert "$CLIENT_CERT_THUMBPRINT" \
        --arg status "mTLS Configured" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")" \
        '. + {
            "ServerCertThumbprint": $server_cert,
            "CACertThumbprint": $ca_cert,
            "ClientCertThumbprint": $client_cert,
            "ConfigurationStatus": $status,
            "ConfigurationTimestamp": $timestamp
        }')
    
    echo "$UPDATED_INFO" > deployment-info.json
    echo -e "${GREEN}✅ Deployment info updated${NC}"
}

# Function to display configuration summary
display_configuration_summary() {
    echo ""
    echo -e "${GREEN}🎉 mTLS configuration completed successfully!${NC}"
    echo -e "${CYAN}📊 Configuration Summary:${NC}"
    echo -e "  • Server App: ${YELLOW}$SERVER_APP_NAME${NC}"
    echo -e "  • Client App: ${YELLOW}$CLIENT_APP_NAME${NC}"
    echo -e "  • Client Certificate Auth: ${YELLOW}Required${NC}"
    echo -e "  • HTTPS Only: ${YELLOW}Enabled${NC}"
    echo -e "  • HTTP/2: ${YELLOW}Enabled${NC}"
    echo ""
    echo -e "${BLUE}📋 Certificate Information:${NC}"
    echo -e "  • Server Cert: ${YELLOW}${SERVER_CERT_THUMBPRINT}${NC}"
    echo -e "  • CA Cert: ${YELLOW}${CA_CERT_THUMBPRINT}${NC}"
    echo -e "  • Client Cert: ${YELLOW}${CLIENT_CERT_THUMBPRINT}${NC}"
    echo ""
    echo -e "${BLUE}🔄 Next steps:${NC}"
    echo -e "  1. Deploy server: ${YELLOW}./03-deploy-server.sh${NC}"
    echo -e "  2. Deploy client: ${YELLOW}./04-deploy-client.sh${NC}"
    echo -e "  3. Verify deployment: ${YELLOW}./05-verify-deployment.sh${NC}"
    echo ""
    echo -e "${YELLOW}💡 Important Notes:${NC}"
    echo -e "  • Make sure certificates are uploaded to Azure App Service Certificate Store"
    echo -e "  • Verify thumbprints match your certificates exactly"
    echo -e "  • Test locally first if possible"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
    
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI is not installed${NC}"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}❌ jq is not installed. Please install it for JSON processing${NC}"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ Not logged into Azure${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Main execution
main() {
    echo -e "${GREEN}🔒 Starting mTLS configuration for Azure Web Apps...${NC}"
    echo ""
    
    check_prerequisites
    load_deployment_info
    get_certificate_thumbprints
    configure_server_settings
    configure_client_settings
    enable_client_certificates
    configure_startup_command
    configure_connection_strings
    update_deployment_info
    display_configuration_summary
}

# Run main function
main "$@"