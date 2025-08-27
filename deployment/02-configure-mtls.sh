#!/bin/bash
# =============================================================================
# Script: 02-configure-mtls.sh
# Description: Configure mTLS settings for Azure Web Apps (no jq dependency)
# Prerequisites: Resources created with 01-create-azure-resources.sh
# 
# Usage: 
#   ./02-configure-mtls.sh [SERVER_CERT] [CA_CERT] [CLIENT_CERT]
#   Or set environment variables:
#   SERVER_CERT_THUMBPRINT=xxx CA_CERT_THUMBPRINT=yyy CLIENT_CERT_THUMBPRINT=zzz ./02-configure-mtls.sh
# =============================================================================

set -e  # Exit on any error

# Parse command line arguments
if [[ $# -eq 3 ]]; then
    SERVER_CERT_THUMBPRINT="$1"
    CA_CERT_THUMBPRINT="$2"
    CLIENT_CERT_THUMBPRINT="$3"
    echo -e "${GREEN}Using thumbprints from command line arguments${NC}"
elif [[ -n "$SERVER_CERT_THUMBPRINT" && -n "$CA_CERT_THUMBPRINT" && -n "$CLIENT_CERT_THUMBPRINT" ]]; then
    echo -e "${GREEN}Using thumbprints from environment variables${NC}"
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to extract JSON values without jq
get_json_value() {
    local json_file="$1"
    local key="$2"
    
    # Use grep and sed to extract values (basic JSON parsing)
    grep "\"$key\"" "$json_file" | sed 's/.*: *"\([^"]*\)".*/\1/' | sed 's/,$//'
}

# Function to load deployment info
load_deployment_info() {
    if [[ ! -f "deployment-info.json" ]]; then
        echo -e "${RED}❌ deployment-info.json not found. Please run 01-create-azure-resources.sh first.${NC}"
        exit 1
    fi
    
    RESOURCE_GROUP=$(get_json_value "deployment-info.json" "ResourceGroup")
    SERVER_APP_NAME=$(get_json_value "deployment-info.json" "ServerAppName")
    CLIENT_APP_NAME=$(get_json_value "deployment-info.json" "ClientAppName")
    SERVER_URL=$(get_json_value "deployment-info.json" "ServerUrl")
    
    echo -e "${BLUE}📋 Loaded deployment configuration:${NC}"
    echo -e "  Resource Group: ${CYAN}$RESOURCE_GROUP${NC}"
    echo -e "  Server App: ${CYAN}$SERVER_APP_NAME${NC}"
    echo -e "  Client App: ${CYAN}$CLIENT_APP_NAME${NC}"
    echo ""
}

# Function to check if already configured
check_if_configured() {
    EXISTING_SERVER_CERT=$(get_json_value "deployment-info.json" "ServerCertThumbprint" 2>/dev/null || echo "")
    EXISTING_CA_CERT=$(get_json_value "deployment-info.json" "CACertThumbprint" 2>/dev/null || echo "")
    EXISTING_CLIENT_CERT=$(get_json_value "deployment-info.json" "ClientCertThumbprint" 2>/dev/null || echo "")
    
    if [[ -n "$EXISTING_SERVER_CERT" && -n "$EXISTING_CA_CERT" && -n "$EXISTING_CLIENT_CERT" ]]; then
        echo -e "${BLUE}ℹ️  mTLS already configured with certificates:${NC}"
        echo -e "  Server: ${YELLOW}$EXISTING_SERVER_CERT${NC}"
        echo -e "  CA: ${YELLOW}$EXISTING_CA_CERT${NC}"
        echo -e "  Client: ${YELLOW}$EXISTING_CLIENT_CERT${NC}"
        echo ""
        
        read -p "Do you want to reconfigure with new certificates? (y/N): " RECONFIGURE
        if [[ ! "$RECONFIGURE" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}✅ Using existing mTLS configuration${NC}"
            return 1  # Skip configuration
        fi
    fi
    return 0  # Proceed with configuration
}

# Function to load thumbprints from config file
load_thumbprints_from_config() {
    local config_file="thumbprints-config.json"
    
    if [[ -f "$config_file" ]]; then
        echo -e "${BLUE}📄 Loading thumbprints from $config_file${NC}"
        
        SERVER_CERT_THUMBPRINT=$(get_json_value "$config_file" "ServerCertThumbprint")
        CA_CERT_THUMBPRINT=$(get_json_value "$config_file" "CACertThumbprint")
        CLIENT_CERT_THUMBPRINT=$(get_json_value "$config_file" "ClientCertThumbprint")
        
        echo -e "${GREEN}✅ Thumbprints loaded from config file${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  thumbprints-config.json not found${NC}"
        return 1
    fi
}

# Function to get certificate thumbprints from user
get_certificate_thumbprints() {
    # First try to load from config file
    if load_thumbprints_from_config; then
        echo -e "${CYAN}Certificate Thumbprints (from config):${NC}"
        echo -e "  Server: ${YELLOW}$SERVER_CERT_THUMBPRINT${NC}"
        echo -e "  CA: ${YELLOW}$CA_CERT_THUMBPRINT${NC}"
        echo -e "  Client: ${YELLOW}$CLIENT_CERT_THUMBPRINT${NC}"
        echo ""
        
        # Check if running in non-interactive mode (for deploy-complete.sh)
        if [[ -n "$NON_INTERACTIVE" || ! -t 0 ]]; then
            echo -e "${GREEN}✅ Using thumbprints from config (non-interactive mode)${NC}"
            return 0
        fi
        
        read -p "Use these thumbprints? (Y/n): " USE_CONFIG
        if [[ "$USE_CONFIG" =~ ^[Nn]$ ]]; then
            echo -e "${YELLOW}Please provide new thumbprints:${NC}"
        else
            return 0  # Use config thumbprints
        fi
    fi
    
    echo -e "${YELLOW}🔑 Certificate Configuration${NC}"
    echo -e "${BLUE}Please provide the certificate thumbprints:${NC}"
    echo ""
    
    # Use existing values as defaults
    if [[ -n "$EXISTING_SERVER_CERT" ]]; then
        read -p "Server Certificate Thumbprint [$EXISTING_SERVER_CERT]: " SERVER_CERT_THUMBPRINT
        SERVER_CERT_THUMBPRINT=${SERVER_CERT_THUMBPRINT:-$EXISTING_SERVER_CERT}
    else
        read -p "Server Certificate Thumbprint: " SERVER_CERT_THUMBPRINT
    fi
    
    if [[ -n "$EXISTING_CA_CERT" ]]; then
        read -p "CA Certificate Thumbprint [$EXISTING_CA_CERT]: " CA_CERT_THUMBPRINT
        CA_CERT_THUMBPRINT=${CA_CERT_THUMBPRINT:-$EXISTING_CA_CERT}
    else
        read -p "CA Certificate Thumbprint: " CA_CERT_THUMBPRINT
    fi
    
    if [[ -n "$EXISTING_CLIENT_CERT" ]]; then
        read -p "Client Certificate Thumbprint [$EXISTING_CLIENT_CERT]: " CLIENT_CERT_THUMBPRINT
        CLIENT_CERT_THUMBPRINT=${CLIENT_CERT_THUMBPRINT:-$EXISTING_CLIENT_CERT}
    else
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
            "WEBSITE_LOAD_CERTIFICATES=*" \
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
            "AzureCertificates__CACertThumbprint=$CA_CERT_THUMBPRINT" \
            "WEBSITE_LOAD_CERTIFICATES=*" \
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

# Function to configure certificate store access
configure_certificate_store_access() {
    echo -e "${YELLOW}🔑 Configuring certificate store access...${NC}"
    
    # Enable access to certificate store for both applications
    echo -e "${BLUE}Enabling certificate store access for server app...${NC}"
    az webapp config set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SERVER_APP_NAME" \
        --generic-configurations '{"WEBSITE_LOAD_CERTIFICATES": "*"}' \
        --output table
    
    echo -e "${BLUE}Enabling certificate store access for client app...${NC}"
    az webapp config set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLIENT_APP_NAME" \
        --generic-configurations '{"WEBSITE_LOAD_CERTIFICATES": "*"}' \
        --output table
    
    echo -e "${GREEN}✅ Certificate store access configured${NC}"
}

# Function to restart applications
restart_applications() {
    echo -e "${YELLOW}🔄 Restarting applications to apply changes...${NC}"
    
    echo -e "${BLUE}Restarting server application...${NC}"
    az webapp restart \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SERVER_APP_NAME" \
        --output table
    
    echo -e "${BLUE}Restarting client application...${NC}"
    az webapp restart \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLIENT_APP_NAME" \
        --output table
    
    echo -e "${GREEN}✅ Applications restarted${NC}"
    echo -e "${BLUE}ℹ️  Waiting for applications to fully start...${NC}"
    sleep 10
}

# Function to update deployment info without jq
update_deployment_info() {
    echo -e "${YELLOW}📄 Updating deployment information...${NC}"
    
    # Create temp file with updated info
    CURRENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    # Read current file and append new fields (simple approach)
    sed 's/}$/,/' deployment-info.json > deployment-info-temp.json
    cat >> deployment-info-temp.json << EOF
  "ServerCertThumbprint": "$SERVER_CERT_THUMBPRINT",
  "CACertThumbprint": "$CA_CERT_THUMBPRINT",
  "ClientCertThumbprint": "$CLIENT_CERT_THUMBPRINT",
  "ConfigurationStatus": "mTLS Configured",
  "ConfigurationTimestamp": "$CURRENT_TIMESTAMP"
}
EOF
    
    mv deployment-info-temp.json deployment-info.json
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
    echo -e "${BLUE}🔄 Configuration Changes Applied:${NC}"
    echo -e "  • Client Certificate Mode: ${YELLOW}Required${NC}"
    echo -e "  • Certificate Store Access: ${YELLOW}Enabled${NC}"
    echo -e "  • Environment Variables: ${YELLOW}Configured${NC}"
    echo -e "  • Applications: ${YELLOW}Restarted${NC}"
    echo ""
    echo -e "${BLUE}🔄 Next steps:${NC}"
    echo -e "  1. Deploy server: ${YELLOW}bash 03-deploy-server.sh${NC}"
    echo -e "  2. Deploy client: ${YELLOW}bash 04-deploy-client.sh${NC}"
    echo -e "  3. Verify deployment: ${YELLOW}bash 05-verify-deployment.sh${NC}"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
    
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI is not installed${NC}"
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
    
    # Check if already configured
    if ! check_if_configured; then
        echo -e "${BLUE}📋 Next steps:${NC}"
        echo -e "  1. Deploy server: ${YELLOW}bash 03-deploy-server.sh${NC}"
        echo -e "  2. Deploy client: ${YELLOW}bash 04-deploy-client.sh${NC}"
        echo -e "  3. Verify deployment: ${YELLOW}bash 05-verify-deployment.sh${NC}"
        return 0
    fi
    
    get_certificate_thumbprints
    configure_server_settings
    configure_client_settings
    enable_client_certificates
    configure_certificate_store_access
    restart_applications
    update_deployment_info
    display_configuration_summary
}

# Run main function
main "$@"