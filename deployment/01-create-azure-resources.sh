#!/bin/bash
# =============================================================================
# Script: 01-create-azure-resources-fast.sh
# Description: Create Azure resources for mTLS (faster version, less verification)
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

echo -e "${GREEN}🚀 Starting Azure resources creation (fast mode)...${NC}"

# Generate unique names
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
UNIQUE_SUFFIX=$(echo "$SUBSCRIPTION_ID" | cut -c 1-8)
SERVER_APP_NAME="${SERVER_APP_NAME}-$UNIQUE_SUFFIX"
CLIENT_APP_NAME="${CLIENT_APP_NAME}-$UNIQUE_SUFFIX"

echo -e "${CYAN}App names: $SERVER_APP_NAME, $CLIENT_APP_NAME${NC}"

# Create resource group
echo -e "${YELLOW}📦 Creating resource group...${NC}"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
echo -e "${GREEN}✅ Resource group created${NC}"

# Create app service plan  
echo -e "${YELLOW}🏗️  Creating App Service Plan...${NC}"
az appservice plan create \
    --name "$APP_SERVICE_PLAN" \
    --resource-group "$RESOURCE_GROUP" \
    --sku "$SKU" \
    --is-linux \
    --output none
echo -e "${GREEN}✅ App Service Plan created${NC}"

# Wait a bit for propagation
echo -e "${BLUE}⏳ Waiting 30 seconds for propagation...${NC}"
sleep 30

# Create both web apps in parallel
echo -e "${YELLOW}🖥️  Creating Web Apps...${NC}"
az webapp create \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$APP_SERVICE_PLAN" \
    --name "$SERVER_APP_NAME" \
    --runtime "DOTNETCORE:8.0" \
    --output none &

az webapp create \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$APP_SERVICE_PLAN" \
    --name "$CLIENT_APP_NAME" \
    --runtime "DOTNETCORE:8.0" \
    --output none &

# Wait for both to complete
wait
echo -e "${GREEN}✅ Web Apps created${NC}"

# Configure HTTPS only and HTTP/2
echo -e "${YELLOW}🔒 Configuring HTTPS and HTTP/2...${NC}"
az webapp update --resource-group "$RESOURCE_GROUP" --name "$SERVER_APP_NAME" --https-only true --output none &
az webapp update --resource-group "$RESOURCE_GROUP" --name "$CLIENT_APP_NAME" --https-only true --output none &
az webapp config set --resource-group "$RESOURCE_GROUP" --name "$SERVER_APP_NAME" --http20-enabled true --output none &
az webapp config set --resource-group "$RESOURCE_GROUP" --name "$CLIENT_APP_NAME" --http20-enabled true --output none &

wait
echo -e "${GREEN}✅ HTTPS and HTTP/2 configured${NC}"

# Save deployment info
echo -e "${YELLOW}📄 Saving deployment info...${NC}"
SERVER_URL="https://$SERVER_APP_NAME.azurewebsites.net"
CLIENT_URL="https://$CLIENT_APP_NAME.azurewebsites.net"

cat > deployment-info.json << EOF
{
  "ResourceGroup": "$RESOURCE_GROUP",
  "Location": "$LOCATION", 
  "AppServicePlan": "$APP_SERVICE_PLAN",
  "ServerAppName": "$SERVER_APP_NAME",
  "ClientAppName": "$CLIENT_APP_NAME",
  "ServerUrl": "$SERVER_URL",
  "ClientUrl": "$CLIENT_URL",
  "DeploymentStatus": "Resources Created",
  "Timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")",
  "SKU": "$SKU"
}
EOF

echo ""
echo -e "${GREEN}🎉 Azure resources created successfully!${NC}"
echo -e "${CYAN}📊 Summary:${NC}"
echo -e "  • Server: ${YELLOW}$SERVER_URL${NC}"
echo -e "  • Client: ${YELLOW}$CLIENT_URL${NC}"
echo ""
echo -e "${BLUE}📋 Next steps:${NC}"
echo -e "  1. Configure mTLS: ${YELLOW}./02-configure-mtls.sh${NC}"
echo -e "  2. Deploy applications with remaining scripts"
echo ""