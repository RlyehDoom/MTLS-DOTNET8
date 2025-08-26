#!/bin/bash
# =============================================================================
# Script: 01-create-azure-resources.sh
# Description: Create Azure resources for mTLS Server and Client deployment
# Prerequisites: Azure CLI installed and logged in (az login)
# =============================================================================

set -e  # Exit on any error

# Default values
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-mtls-demo}"
LOCATION="${LOCATION:-centralus}"
APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-asp-mtls-demo}"
SERVER_APP_NAME="${SERVER_APP_NAME:-mtls-server}"
CLIENT_APP_NAME="${CLIENT_APP_NAME:-mtls-client}"
SKU="${SKU:-B1}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting Azure resources creation for mTLS demo...${NC}"
echo -e "${BLUE}Configuration:${NC}"
echo -e "  Resource Group: ${CYAN}$RESOURCE_GROUP${NC}"
echo -e "  Location: ${CYAN}$LOCATION${NC}"
echo -e "  App Service Plan: ${CYAN}$APP_SERVICE_PLAN${NC}"
echo -e "  Server App: ${CYAN}$SERVER_APP_NAME${NC}"
echo -e "  Client App: ${CYAN}$CLIENT_APP_NAME${NC}"
echo -e "  SKU: ${CYAN}$SKU${NC}"
echo ""

# Function to check if Azure CLI is installed and user is logged in
check_prerequisites() {
    echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
    
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI is not installed. Please install it first.${NC}"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ Not logged into Azure. Please run 'az login' first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to create resource group
create_resource_group() {
    echo -e "${YELLOW}📦 Creating resource group: $RESOURCE_GROUP${NC}"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        echo -e "${BLUE}ℹ️  Resource group already exists${NC}"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --output table
        echo -e "${GREEN}✅ Resource group created successfully${NC}"
        echo -e "${BLUE}⏳ Waiting 30 seconds for resource group propagation...${NC}"
        sleep 30
    fi
}

# Function to create App Service Plan
create_app_service_plan() {
    echo -e "${YELLOW}🏗️  Creating App Service Plan: $APP_SERVICE_PLAN${NC}"
    
    if az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        echo -e "${BLUE}ℹ️  App Service Plan already exists${NC}"
    else
        az appservice plan create \
            --name "$APP_SERVICE_PLAN" \
            --resource-group "$RESOURCE_GROUP" \
            --sku "$SKU" \
            --is-linux \
            --output table
        echo -e "${GREEN}✅ App Service Plan created successfully${NC}"
        echo -e "${BLUE}⏳ Waiting 45 seconds for App Service Plan propagation...${NC}"
        sleep 45
    fi
}

# Function to generate unique but predictable app names
generate_unique_names() {
    echo -e "${YELLOW}🔍 Generating unique app names...${NC}"
    
    # Get subscription ID to make names unique but predictable
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    UNIQUE_SUFFIX=$(echo "$SUBSCRIPTION_ID" | cut -c 1-8)
    
    # Update names to be unique
    SERVER_APP_NAME="${SERVER_APP_NAME:-mtls-server}-$UNIQUE_SUFFIX"
    CLIENT_APP_NAME="${CLIENT_APP_NAME:-mtls-client}-$UNIQUE_SUFFIX"
    
    echo -e "${CYAN}Generated app names:${NC}"
    echo -e "  Server: ${YELLOW}$SERVER_APP_NAME${NC}"
    echo -e "  Client: ${YELLOW}$CLIENT_APP_NAME${NC}"
    echo ""
}

# Function to create web apps
create_web_apps() {
    echo -e "${YELLOW}🖥️  Creating Server Web App: $SERVER_APP_NAME${NC}"
    
    if az webapp show --name "$SERVER_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        echo -e "${BLUE}ℹ️  Server app already exists${NC}"
    else
        if az webapp create \
            --resource-group "$RESOURCE_GROUP" \
            --plan "$APP_SERVICE_PLAN" \
            --name "$SERVER_APP_NAME" \
            --runtime "DOTNETCORE:8.0" \
            --output table; then
            echo -e "${GREEN}✅ Server Web App created successfully${NC}"
            echo -e "${BLUE}⏳ Waiting 60 seconds for Server Web App propagation...${NC}"
            sleep 60
        else
            echo -e "${RED}❌ Failed to create Server Web App${NC}"
            exit 1
        fi
        
        # Verify server app was created with retries
        echo -e "${BLUE}🔍 Verifying Server Web App creation...${NC}"
        local max_attempts=5
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            if az webapp show --name "$SERVER_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                echo -e "${GREEN}✅ Server Web App verified successfully${NC}"
                break
            else
                if [[ $attempt -lt $max_attempts ]]; then
                    echo -e "${YELLOW}⚠️  Verification attempt $attempt failed, retrying in 15 seconds...${NC}"
                    sleep 15
                else
                    echo -e "${RED}❌ Server Web App verification failed after $max_attempts attempts${NC}"
                    echo -e "${BLUE}ℹ️  You can check the resource in Azure Portal and continue manually${NC}"
                    exit 1
                fi
            fi
            ((attempt++))
        done
    fi
    
    echo -e "${YELLOW}💻 Creating Client Web App: $CLIENT_APP_NAME${NC}"
    
    if az webapp show --name "$CLIENT_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        echo -e "${BLUE}ℹ️  Client app already exists${NC}"
    else
        if az webapp create \
            --resource-group "$RESOURCE_GROUP" \
            --plan "$APP_SERVICE_PLAN" \
            --name "$CLIENT_APP_NAME" \
            --runtime "DOTNETCORE:8.0" \
            --output table; then
            echo -e "${GREEN}✅ Client Web App created successfully${NC}"
            echo -e "${BLUE}⏳ Waiting 60 seconds for Client Web App propagation...${NC}"
            sleep 60
        else
            echo -e "${RED}❌ Failed to create Client Web App${NC}"
            exit 1
        fi
        
        # Verify client app was created with retries
        echo -e "${BLUE}🔍 Verifying Client Web App creation...${NC}"
        local max_attempts=5
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            if az webapp show --name "$CLIENT_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                echo -e "${GREEN}✅ Client Web App verified successfully${NC}"
                break
            else
                if [[ $attempt -lt $max_attempts ]]; then
                    echo -e "${YELLOW}⚠️  Verification attempt $attempt failed, retrying in 15 seconds...${NC}"
                    sleep 15
                else
                    echo -e "${RED}❌ Client Web App verification failed after $max_attempts attempts${NC}"
                    echo -e "${BLUE}ℹ️  You can check the resource in Azure Portal and continue manually${NC}"
                    echo -e "${BLUE}ℹ️  The resource might exist but need more time to be fully available${NC}"
                    
                    # Try to show what resources exist for debugging
                    echo -e "${CYAN}📋 Current resources in resource group:${NC}"
                    az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || echo "Could not list resources"
                    
                    exit 1
                fi
            fi
            ((attempt++))
        done
    fi
}

# Function to enable HTTPS only
enable_https_only() {
    echo -e "${YELLOW}🔒 Enabling HTTPS Only for both apps...${NC}"
    
    az webapp update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SERVER_APP_NAME" \
        --https-only true \
        --output none
    
    az webapp update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLIENT_APP_NAME" \
        --https-only true \
        --output none
    
    echo -e "${GREEN}✅ HTTPS Only enabled for both apps${NC}"
}

# Function to enable HTTP/2
enable_http2() {
    echo -e "${YELLOW}🚀 Enabling HTTP/2 support...${NC}"
    
    az webapp config set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SERVER_APP_NAME" \
        --http20-enabled true \
        --output none
    
    az webapp config set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLIENT_APP_NAME" \
        --http20-enabled true \
        --output none
    
    echo -e "${GREEN}✅ HTTP/2 enabled for both apps${NC}"
}

# Function to save deployment information
save_deployment_info() {
    echo -e "${YELLOW}📄 Saving deployment information...${NC}"
    
    DEPLOYMENT_INFO=$(cat << EOF
{
  "ResourceGroup": "$RESOURCE_GROUP",
  "Location": "$LOCATION", 
  "AppServicePlan": "$APP_SERVICE_PLAN",
  "ServerAppName": "$SERVER_APP_NAME",
  "ClientAppName": "$CLIENT_APP_NAME",
  "ServerUrl": "https://$SERVER_APP_NAME.azurewebsites.net",
  "ClientUrl": "https://$CLIENT_APP_NAME.azurewebsites.net",
  "DeploymentStatus": "Resources Created",
  "Timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")",
  "SKU": "$SKU"
}
EOF
    )
    
    echo "$DEPLOYMENT_INFO" > deployment-info.json
    echo -e "${GREEN}✅ Deployment info saved to deployment-info.json${NC}"
}

# Function to display results
display_results() {
    echo ""
    echo -e "${GREEN}🎉 Azure resources created successfully!${NC}"
    echo -e "${CYAN}📊 Summary:${NC}"
    echo -e "  • Resource Group: ${YELLOW}$RESOURCE_GROUP${NC}"
    echo -e "  • Server URL: ${YELLOW}https://$SERVER_APP_NAME.azurewebsites.net${NC}"
    echo -e "  • Client URL: ${YELLOW}https://$CLIENT_APP_NAME.azurewebsites.net${NC}"
    echo ""
    echo -e "${BLUE}📋 Next steps:${NC}"
    echo -e "  1. Configure mTLS settings: ${YELLOW}./02-configure-mtls.sh${NC}"
    echo -e "  2. Deploy server application: ${YELLOW}./03-deploy-server.sh${NC}"
    echo -e "  3. Deploy client application: ${YELLOW}./04-deploy-client.sh${NC}"
    echo -e "  4. Verify deployment: ${YELLOW}./05-verify-deployment.sh${NC}"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    generate_unique_names
    create_resource_group
    create_app_service_plan
    create_web_apps
    enable_https_only
    enable_http2
    save_deployment_info
    display_results
}

# Run main function
main "$@"