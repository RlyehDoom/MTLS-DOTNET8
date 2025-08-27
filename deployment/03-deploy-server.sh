#!/bin/bash
# =============================================================================
# Script: 03-deploy-server.sh
# Description: Build and deploy mTLS Server application to Azure
# Prerequisites: Azure resources and mTLS configured
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
SERVER_PROJECT_PATH="$PROJECT_ROOT/src/mTLS.Server"
PUBLISH_DIR="$SERVER_PROJECT_PATH/publish"
DEPLOYMENT_ZIP="$SCRIPT_DIR/server-deployment.zip"

# Function to load deployment info
load_deployment_info() {
    if [[ ! -f "deployment-info.json" ]]; then
        echo -e "${RED}❌ deployment-info.json not found. Please run previous scripts first.${NC}"
        exit 1
    fi
    
    RESOURCE_GROUP=$(grep '"ResourceGroup"' deployment-info.json | sed 's/.*: *"\([^"]*\)".*/\1/')
    SERVER_APP_NAME=$(grep '"ServerAppName"' deployment-info.json | sed 's/.*: *"\([^"]*\)".*/\1/')
    SERVER_URL=$(grep '"ServerUrl"' deployment-info.json | sed 's/.*: *"\([^"]*\)".*/\1/')
    
    echo -e "${BLUE}📋 Loaded deployment configuration:${NC}"
    echo -e "  Resource Group: ${CYAN}$RESOURCE_GROUP${NC}"
    echo -e "  Server App: ${CYAN}$SERVER_APP_NAME${NC}"
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
    
    
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ Not logged into Azure${NC}"
        exit 1
    fi
    
    if [[ ! -d "$SERVER_PROJECT_PATH" ]]; then
        echo -e "${RED}❌ Server project not found at: $SERVER_PROJECT_PATH${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to clean previous builds
clean_previous_builds() {
    echo -e "${YELLOW}🧹 Cleaning previous builds...${NC}"
    
    cd "$SERVER_PROJECT_PATH"
    
    # Clean build artifacts first
    dotnet clean --configuration Release --verbosity quiet || true
    
    # Remove bin and obj directories
    if [[ -d "bin" ]]; then
        rm -rf bin
        echo -e "${BLUE}  • Removed bin directory${NC}"
    fi
    
    if [[ -d "obj" ]]; then
        rm -rf obj  
        echo -e "${BLUE}  • Removed obj directory${NC}"
    fi
    
    if [[ -d "$PUBLISH_DIR" ]]; then
        rm -rf "$PUBLISH_DIR"
        echo -e "${BLUE}  • Removed previous publish directory${NC}"
    fi
    
    if [[ -f "$DEPLOYMENT_ZIP" ]]; then
        rm -f "$DEPLOYMENT_ZIP"
        echo -e "${BLUE}  • Removed previous deployment package${NC}"
    fi
    
    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

# Function to restore dependencies
restore_dependencies() {
    echo -e "${YELLOW}📦 Restoring NuGet packages...${NC}"
    
    cd "$SERVER_PROJECT_PATH"
    
    # Clear NuGet cache if restore fails
    if ! dotnet restore --verbosity quiet; then
        echo -e "${YELLOW}⚠️  Initial restore failed, clearing NuGet cache and retrying...${NC}"
        dotnet nuget locals all --clear
        dotnet restore --verbosity minimal --force
    fi
    
    echo -e "${GREEN}✅ Dependencies restored${NC}"
}

# Function to build the server project
build_server_project() {
    echo -e "${YELLOW}🔨 Building server project...${NC}"
    
    cd "$SERVER_PROJECT_PATH"
    
    # Build the project
    dotnet build \
        --configuration Release \
        --no-restore \
        --verbosity minimal
    
    echo -e "${GREEN}✅ Server project built successfully${NC}"
}

# Function to publish the server project
publish_server_project() {
    echo -e "${YELLOW}📦 Publishing server project...${NC}"
    
    cd "$SERVER_PROJECT_PATH"
    
    # Publish the project
    dotnet publish \
        --configuration Release \
        --output "$PUBLISH_DIR" \
        --no-build \
        --no-restore \
        --verbosity minimal \
        --self-contained false
    
    echo -e "${GREEN}✅ Server project published to: $PUBLISH_DIR${NC}"
}

# Function to create deployment package
create_deployment_package() {
    echo -e "${YELLOW}📦 Creating deployment package...${NC}"
    
    cd "$PUBLISH_DIR"
    
    # For Azure App Service, move wwwroot contents to root level
    # This allows ASP.NET Core to serve static files from the root alongside API endpoints
    if [[ -d "wwwroot" ]]; then
        echo -e "${BLUE}📁 wwwroot contents found:${NC}"
        ls -la wwwroot/ | head -5
        
        # Move wwwroot contents to root level
        echo -e "${BLUE}📦 Moving wwwroot contents to root level for Azure deployment...${NC}"
        if [[ -n "$(ls -A wwwroot/ 2>/dev/null)" ]]; then
            # Only move if wwwroot has content and won't overwrite existing files
            for file in wwwroot/*; do
                if [[ -f "$file" ]]; then
                    filename=$(basename "$file")
                    if [[ ! -f "$filename" ]]; then
                        mv "$file" .
                        echo -e "${BLUE}  • Moved $filename to root${NC}"
                    else
                        echo -e "${YELLOW}  • Skipped $filename (already exists in root)${NC}"
                    fi
                fi
            done
            
            # Remove empty wwwroot directory
            if [[ -z "$(ls -A wwwroot/ 2>/dev/null)" ]]; then
                rmdir wwwroot
                echo -e "${BLUE}  • Removed empty wwwroot directory${NC}"
            fi
        fi
        echo -e "${GREEN}✅ Static files prepared for root-level serving${NC}"
    else
        echo -e "${YELLOW}⚠️  wwwroot directory not found in publish output${NC}"
    fi
    
    # List contents for verification
    echo -e "${BLUE}📁 Package contents:${NC}"
    ls -la | head -10
    
    # Create zip file - Azure App Service requires ZIP format
    if command -v zip &> /dev/null; then
        # Include all files and directories recursively
        zip -r "$DEPLOYMENT_ZIP" . -q
        echo -e "${BLUE}📦 Created ZIP package with all files${NC}"
    elif command -v 7z &> /dev/null; then
        # Use 7-Zip if available
        7z a "$DEPLOYMENT_ZIP" . -r > /dev/null
        echo -e "${BLUE}📦 Created ZIP package with 7-Zip${NC}"
    else
        # Try using PowerShell on Windows
        if [[ "$OS" == "Windows_NT" ]]; then
            powershell.exe -Command "Compress-Archive -Path '.\*' -DestinationPath '$DEPLOYMENT_ZIP' -Force"
            echo -e "${BLUE}📦 Created ZIP package with PowerShell${NC}"
        else
            echo -e "${RED}❌ No ZIP utility found. Please install zip, 7z, or use Windows${NC}"
            exit 1
        fi
    fi
    
    # Get package size and verify contents
    PACKAGE_SIZE=$(du -h "$DEPLOYMENT_ZIP" | cut -f1)
    
    # Verify ZIP contents
    if command -v zip &> /dev/null && [[ "$DEPLOYMENT_ZIP" == *.zip ]]; then
        echo -e "${BLUE}🔍 Verifying ZIP contents:${NC}"
        if zip -T "$DEPLOYMENT_ZIP" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ ZIP file integrity verified${NC}"
            # Show sample of contents
            unzip -l "$DEPLOYMENT_ZIP" | grep -E "(index\.html|\.dll|\.json)" | head -3 || echo -e "${YELLOW}⚠️  No expected files found in ZIP${NC}"
        else
            echo -e "${RED}❌ ZIP file integrity check failed${NC}"
        fi
    fi
    
    echo -e "${GREEN}✅ Deployment package created: ${CYAN}$DEPLOYMENT_ZIP${NC} (${PACKAGE_SIZE})"
}

# Function to deploy to Azure
deploy_to_azure() {
    echo -e "${YELLOW}🚀 Deploying to Azure Web App: $SERVER_APP_NAME${NC}"
    echo -e "${BLUE}  This may take a few minutes...${NC}"
    
    cd "$SCRIPT_DIR"
    
    # Deploy the package
    az webapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SERVER_APP_NAME" \
        --src "$(basename "$DEPLOYMENT_ZIP")" \
        --timeout 600 \
        --output table
    
    echo -e "${GREEN}✅ Server deployed successfully to Azure${NC}"
}

# Function to wait for deployment
wait_for_deployment() {
    echo -e "${YELLOW}⏳ Waiting for deployment to complete...${NC}"
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo -e "${BLUE}  Checking deployment status (attempt $attempt/$max_attempts)...${NC}"
        
        # Check if the health endpoint responds
        if curl -s -f -m 10 "$SERVER_URL/health" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Deployment is live and responding${NC}"
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            echo -e "${YELLOW}  Waiting 10 seconds before next check...${NC}"
            sleep 10
        fi
        
        ((attempt++))
    done
    
    echo -e "${YELLOW}⚠️  Deployment completed but health check failed. App might need more time to start.${NC}"
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
    
    # Update deployment info without jq
    CURRENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    # Check if already has server deployment info
    if grep -q "ServerDeploymentStatus" deployment-info.json; then
        # Update existing entry
        sed -i "s/\"ServerDeploymentTimestamp\": \"[^\"]*\"/\"ServerDeploymentTimestamp\": \"$CURRENT_TIMESTAMP\"/" deployment-info.json
        sed -i 's/"ServerStatus": "[^"]*"/"ServerStatus": "Running"/' deployment-info.json
        sed -i 's/"ServerDeploymentStatus": "[^"]*"/"ServerDeploymentStatus": "Server Deployed"/' deployment-info.json
    else
        # Add new fields
        sed 's/}$/,/' deployment-info.json > deployment-info-temp.json
        cat >> deployment-info-temp.json << EOF
  "ServerStatus": "Running",
  "ServerDeploymentStatus": "Server Deployed",
  "ServerDeploymentTimestamp": "$CURRENT_TIMESTAMP"
}
EOF
        mv deployment-info-temp.json deployment-info.json
    fi
    
    echo -e "${GREEN}✅ Deployment info updated${NC}"
}

# Function to test basic endpoints
test_endpoints() {
    echo -e "${YELLOW}🧪 Testing server endpoints...${NC}"
    
    # Test health endpoint
    echo -e "${BLUE}  Testing /health endpoint...${NC}"
    if curl -s -f -m 10 "$SERVER_URL/health" > /dev/null; then
        echo -e "${GREEN}  ✅ Health endpoint responding${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Health endpoint not responding yet${NC}"
    fi
    
    # Test weatherforecast endpoint
    echo -e "${BLUE}  Testing /weatherforecast endpoint...${NC}"
    if curl -s -f -m 10 "$SERVER_URL/weatherforecast" > /dev/null; then
        echo -e "${GREEN}  ✅ WeatherForecast endpoint responding${NC}"
    else
        echo -e "${YELLOW}  ⚠️  WeatherForecast endpoint not responding yet${NC}"
    fi
    
    echo -e "${BLUE}  Note: mTLS endpoints require client certificates${NC}"
}

# Function to display results
display_results() {
    echo ""
    echo -e "${GREEN}🎉 Server deployment completed successfully!${NC}"
    echo -e "${CYAN}📊 Deployment Summary:${NC}"
    echo -e "  • Application: ${YELLOW}$SERVER_APP_NAME${NC}"
    echo -e "  • URL: ${YELLOW}$SERVER_URL${NC}"
    echo -e "  • Status: ${YELLOW}Deployed${NC}"
    echo ""
    echo -e "${BLUE}🔗 Available Endpoints:${NC}"
    echo -e "  • Health Check: ${CYAN}$SERVER_URL/health${NC}"
    echo -e "  • Weather API: ${CYAN}$SERVER_URL/weatherforecast${NC}"
    echo -e "  • mTLS Test: ${CYAN}$SERVER_URL/mtls-test${NC} ${YELLOW}(requires client cert)${NC}"
    echo -e "  • Swagger UI: ${CYAN}$SERVER_URL/swagger${NC}"
    echo ""
    echo -e "${BLUE}📋 Next steps:${NC}"
    echo -e "  1. Deploy client: ${YELLOW}./04-deploy-client.sh${NC}"
    echo -e "  2. Verify deployment: ${YELLOW}./05-verify-deployment.sh${NC}"
    echo ""
}

# Main execution
main() {
    echo -e "${GREEN}🚀 Starting mTLS Server deployment...${NC}"
    echo ""
    
    check_prerequisites
    load_deployment_info
    clean_previous_builds
    restore_dependencies
    build_server_project
    publish_server_project
    create_deployment_package
    deploy_to_azure
    wait_for_deployment
    cleanup
    update_deployment_info
    test_endpoints
    display_results
}

# Run main function
main "$@"