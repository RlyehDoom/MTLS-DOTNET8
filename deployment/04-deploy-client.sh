#!/bin/bash
# =============================================================================
# Script: 04-deploy-client.sh
# Description: Build and deploy mTLS Client application to Azure
# Prerequisites: Azure resources, mTLS configured, and server deployed
# =============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory and project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CLIENT_PROJECT_PATH="$PROJECT_ROOT/src/mTLS.Client"
PUBLISH_DIR="$CLIENT_PROJECT_PATH/publish"
DEPLOYMENT_ZIP="$SCRIPT_DIR/client-deployment.zip"

# Function to load deployment info
load_deployment_info() {
    if [[ ! -f "deployment-info.json" ]]; then
        echo -e "${RED}❌ deployment-info.json not found. Please run previous scripts first.${NC}"
        exit 1
    fi
    
    RESOURCE_GROUP=$(cat deployment-info.json | jq -r '.ResourceGroup')
    CLIENT_APP_NAME=$(cat deployment-info.json | jq -r '.ClientAppName')
    CLIENT_URL=$(cat deployment-info.json | jq -r '.ClientUrl')
    SERVER_URL=$(cat deployment-info.json | jq -r '.ServerUrl')
    
    echo -e "${BLUE}📋 Loaded deployment configuration:${NC}"
    echo -e "  Resource Group: ${CYAN}$RESOURCE_GROUP${NC}"
    echo -e "  Client App: ${CYAN}$CLIENT_APP_NAME${NC}"
    echo -e "  Client URL: ${CYAN}$CLIENT_URL${NC}"
    echo -e "  Server URL: ${CYAN}$SERVER_URL${NC}"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
    
    if ! command -v dotnet &> /dev/null; then
        echo -e "${RED}❌ .NET CLI is not installed${NC}"
        exit 1
    fi
    
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI is not installed${NC}"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}❌ jq is not installed${NC}"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ Not logged into Azure${NC}"
        exit 1
    fi
    
    if [[ ! -d "$CLIENT_PROJECT_PATH" ]]; then
        echo -e "${RED}❌ Client project not found at: $CLIENT_PROJECT_PATH${NC}"
        exit 1
    fi
    
    # Check if server is deployed
    SERVER_STATUS=$(cat deployment-info.json | jq -r '.ServerStatus // "Unknown"')
    if [[ "$SERVER_STATUS" != "Running" ]]; then
        echo -e "${YELLOW}⚠️  Server status is: $SERVER_STATUS${NC}"
        echo -e "${YELLOW}  Consider deploying server first: ./03-deploy-server.sh${NC}"
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to clean previous builds
clean_previous_builds() {
    echo -e "${YELLOW}🧹 Cleaning previous builds...${NC}"
    
    if [[ -d "$PUBLISH_DIR" ]]; then
        rm -rf "$PUBLISH_DIR"
        echo -e "${BLUE}  • Removed previous publish directory${NC}"
    fi
    
    if [[ -f "$DEPLOYMENT_ZIP" ]]; then
        rm -f "$DEPLOYMENT_ZIP"
        echo -e "${BLUE}  • Removed previous deployment package${NC}"
    fi
    
    # Clean build artifacts
    cd "$CLIENT_PROJECT_PATH"
    dotnet clean --configuration Release --verbosity quiet
    
    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

# Function to restore dependencies
restore_dependencies() {
    echo -e "${YELLOW}📦 Restoring NuGet packages...${NC}"
    
    cd "$CLIENT_PROJECT_PATH"
    dotnet restore --verbosity quiet
    
    echo -e "${GREEN}✅ Dependencies restored${NC}"
}

# Function to build the client project
build_client_project() {
    echo -e "${YELLOW}🔨 Building client project...${NC}"
    
    cd "$CLIENT_PROJECT_PATH"
    
    # Build the project
    dotnet build \
        --configuration Release \
        --no-restore \
        --verbosity minimal
    
    echo -e "${GREEN}✅ Client project built successfully${NC}"
}

# Function to publish the client project
publish_client_project() {
    echo -e "${YELLOW}📦 Publishing client project...${NC}"
    
    cd "$CLIENT_PROJECT_PATH"
    
    # Publish the project
    dotnet publish \
        --configuration Release \
        --output "$PUBLISH_DIR" \
        --no-build \
        --no-restore \
        --verbosity minimal \
        --self-contained false
    
    echo -e "${GREEN}✅ Client project published to: $PUBLISH_DIR${NC}"
}

# Function to create deployment package
create_deployment_package() {
    echo -e "${YELLOW}📦 Creating deployment package...${NC}"
    
    cd "$PUBLISH_DIR"
    
    # Create zip file
    if command -v zip &> /dev/null; then
        zip -r "$DEPLOYMENT_ZIP" . -q
    else
        # Fallback for systems without zip command
        tar -czf "${DEPLOYMENT_ZIP%.zip}.tar.gz" .
        DEPLOYMENT_ZIP="${DEPLOYMENT_ZIP%.zip}.tar.gz"
    fi
    
    # Get package size
    PACKAGE_SIZE=$(du -h "$DEPLOYMENT_ZIP" | cut -f1)
    
    echo -e "${GREEN}✅ Deployment package created: ${CYAN}$DEPLOYMENT_ZIP${NC} (${PACKAGE_SIZE})"
}

# Function to deploy to Azure
deploy_to_azure() {
    echo -e "${YELLOW}🚀 Deploying to Azure Web App: $CLIENT_APP_NAME${NC}"
    echo -e "${BLUE}  This may take a few minutes...${NC}"
    
    cd "$SCRIPT_DIR"
    
    # Deploy the package
    az webapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLIENT_APP_NAME" \
        --src "$(basename "$DEPLOYMENT_ZIP")" \
        --timeout 600 \
        --output table
    
    echo -e "${GREEN}✅ Client deployed successfully to Azure${NC}"
}

# Function to wait for deployment
wait_for_deployment() {
    echo -e "${YELLOW}⏳ Waiting for deployment to complete...${NC}"
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo -e "${BLUE}  Checking deployment status (attempt $attempt/$max_attempts)...${NC}"
        
        # Check if the home endpoint responds
        if curl -s -f -m 10 "$CLIENT_URL/" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Deployment is live and responding${NC}"
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            echo -e "${YELLOW}  Waiting 10 seconds before next check...${NC}"
            sleep 10
        fi
        
        ((attempt++))
    done
    
    echo -e "${YELLOW}⚠️  Deployment completed but connectivity check failed. App might need more time to start.${NC}"
}

# Function to cleanup temporary files
cleanup() {
    echo -e "${YELLOW}🧹 Cleaning up temporary files...${NC}"
    
    if [[ -f "$DEPLOYMENT_ZIP" ]]; then
        rm -f "$DEPLOYMENT_ZIP"
        echo -e "${BLUE}  • Removed deployment package${NC}"
    fi
    
    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

# Function to update deployment info
update_deployment_info() {
    echo -e "${YELLOW}📄 Updating deployment information...${NC}"
    
    # Read existing deployment info
    DEPLOYMENT_INFO=$(cat deployment-info.json)
    
    # Update with client deployment status
    UPDATED_INFO=$(echo "$DEPLOYMENT_INFO" | jq \
        --arg status "Client Deployed" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")" \
        '. + {
            "ClientStatus": "Running",
            "ClientDeploymentStatus": $status,
            "ClientDeploymentTimestamp": $timestamp,
            "DeploymentStatus": "Completed"
        }')
    
    echo "$UPDATED_INFO" > deployment-info.json
    echo -e "${GREEN}✅ Deployment info updated${NC}"
}

# Function to test basic endpoints
test_endpoints() {
    echo -e "${YELLOW}🧪 Testing client endpoints...${NC}"
    
    # Test home endpoint
    echo -e "${BLUE}  Testing / (home) endpoint...${NC}"
    if curl -s -f -m 10 "$CLIENT_URL/" > /dev/null; then
        echo -e "${GREEN}  ✅ Home endpoint responding${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Home endpoint not responding yet${NC}"
    fi
    
    # Test cert-info endpoint
    echo -e "${BLUE}  Testing /cert-info endpoint...${NC}"
    if curl -s -f -m 10 "$CLIENT_URL/cert-info" > /dev/null; then
        echo -e "${GREEN}  ✅ Cert-info endpoint responding${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Cert-info endpoint not responding yet${NC}"
    fi
    
    echo -e "${BLUE}  Note: /test-server endpoint requires mTLS communication with server${NC}"
}

# Function to test server connectivity
test_server_connectivity() {
    echo -e "${YELLOW}🔗 Testing server connectivity...${NC}"
    
    # Test if client can reach server's public endpoints
    echo -e "${BLUE}  Testing client -> server connectivity...${NC}"
    if curl -s -f -m 10 "$SERVER_URL/health" > /dev/null; then
        echo -e "${GREEN}  ✅ Client can reach server${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Client cannot reach server (this might be expected if server requires mTLS)${NC}"
    fi
}

# Function to display results
display_results() {
    echo ""
    echo -e "${GREEN}🎉 Client deployment completed successfully!${NC}"
    echo -e "${CYAN}📊 Deployment Summary:${NC}"
    echo -e "  • Application: ${YELLOW}$CLIENT_APP_NAME${NC}"
    echo -e "  • URL: ${YELLOW}$CLIENT_URL${NC}"
    echo -e "  • Status: ${YELLOW}Deployed${NC}"
    echo ""
    echo -e "${BLUE}🔗 Available Endpoints:${NC}"
    echo -e "  • Home: ${CYAN}$CLIENT_URL/${NC}"
    echo -e "  • Certificate Info: ${CYAN}$CLIENT_URL/cert-info${NC}"
    echo -e "  • Test Server: ${CYAN}$CLIENT_URL/test-server${NC} ${YELLOW}(tests mTLS)${NC}"
    echo ""
    echo -e "${BLUE}🔄 Complete Deployment Status:${NC}"
    echo -e "  • Server: ${CYAN}$SERVER_URL${NC}"
    echo -e "  • Client: ${CYAN}$CLIENT_URL${NC}"
    echo -e "  • mTLS: ${YELLOW}Configured${NC}"
    echo ""
    echo -e "${BLUE}📋 Next steps:${NC}"
    echo -e "  1. Verify deployment: ${YELLOW}./05-verify-deployment.sh${NC}"
    echo -e "  2. Test mTLS functionality manually"
    echo -e "  3. Upload certificates to Azure if not done yet"
    echo ""
}

# Main execution
main() {
    echo -e "${GREEN}🚀 Starting mTLS Client deployment...${NC}"
    echo ""
    
    check_prerequisites
    load_deployment_info
    clean_previous_builds
    restore_dependencies
    build_client_project
    publish_client_project
    create_deployment_package
    deploy_to_azure
    wait_for_deployment
    cleanup
    update_deployment_info
    test_endpoints
    test_server_connectivity
    display_results
}

# Run main function
main "$@"