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
    
    RESOURCE_GROUP=$(grep '"ResourceGroup"' deployment-info.json | sed 's/.*: *"\([^"]*\)".*/\1/')
    CLIENT_APP_NAME=$(grep '"ClientAppName"' deployment-info.json | sed 's/.*: *"\([^"]*\)".*/\1/')
    CLIENT_URL=$(grep '"ClientUrl"' deployment-info.json | sed 's/.*: *"\([^"]*\)".*/\1/')
    SERVER_URL=$(grep '"ServerUrl"' deployment-info.json | sed 's/.*: *"\([^"]*\)".*/\1/')
    
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
    
    
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ Not logged into Azure${NC}"
        exit 1
    fi
    
    if [[ ! -d "$CLIENT_PROJECT_PATH" ]]; then
        echo -e "${RED}❌ Client project not found at: $CLIENT_PROJECT_PATH${NC}"
        exit 1
    fi
    
    # Check if server is deployed
    SERVER_STATUS=$(grep '"ServerStatus"' deployment-info.json | sed 's/.*: *"\([^"]*\)".*/\1/' || echo "Unknown")
    if [[ "$SERVER_STATUS" != "Running" ]]; then
        echo -e "${YELLOW}⚠️  Server status is: $SERVER_STATUS${NC}"
        echo -e "${YELLOW}  Consider deploying server first: ./03-deploy-server.sh${NC}"
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to clean previous builds
clean_previous_builds() {
    echo -e "${YELLOW}🧹 Cleaning previous builds...${NC}"
    
    cd "$CLIENT_PROJECT_PATH"
    
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
    
    cd "$CLIENT_PROJECT_PATH"
    
    # Clear NuGet cache if restore fails
    if ! dotnet restore --verbosity quiet; then
        echo -e "${YELLOW}⚠️  Initial restore failed, clearing NuGet cache and retrying...${NC}"
        dotnet nuget locals all --clear
        dotnet restore --verbosity minimal --force
    fi
    
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

# Function to prepare certificates and static files
prepare_deployment_files() {
    echo -e "${YELLOW}📁 Preparing deployment files...${NC}"
    
    cd "$PUBLISH_DIR"
    
    # Check for nested publish directory and fix if found
    if [[ -d "publish" ]]; then
        echo -e "${YELLOW}⚠️  Found nested publish directory, fixing deployment structure...${NC}"
        
        # Move all files from nested publish to current level
        if [[ -n "$(ls -A publish/ 2>/dev/null)" ]]; then
            mv publish/* . 2>/dev/null || true
            rmdir publish 2>/dev/null || true
            echo -e "${BLUE}  • Fixed nested publish directory structure${NC}"
        fi
    fi
    
    # Copy certificate files for fallback support
    echo -e "${BLUE}📄 Copying certificate files for Azure fallback...${NC}"
    if [[ ! -d "Certs" ]]; then
        mkdir -p Certs
    fi
    
    # Copy PFX certificates from source
    if [[ -f "$CLIENT_PROJECT_PATH/Certs/dev-env.pfx" ]]; then
        cp "$CLIENT_PROJECT_PATH/Certs/dev-env.pfx" Certs/
        echo -e "${BLUE}  • Copied server certificate${NC}"
    fi
    
    if [[ -f "$CLIENT_PROJECT_PATH/Certs/dev-env_client.pfx" ]]; then
        cp "$CLIENT_PROJECT_PATH/Certs/dev-env_client.pfx" Certs/
        echo -e "${BLUE}  • Copied client certificate${NC}"
    fi
    
    if [[ -f "$CLIENT_PROJECT_PATH/Certs/ca.crt" ]]; then
        cp "$CLIENT_PROJECT_PATH/Certs/ca.crt" Certs/
        echo -e "${BLUE}  • Copied CA certificate${NC}"
    fi
    
    echo -e "${GREEN}✅ Certificate files prepared for deployment${NC}"
}

# Function to create deployment package
create_deployment_package() {
    echo -e "${YELLOW}📦 Creating deployment package...${NC}"
    
    cd "$PUBLISH_DIR"
    
    # Check for nested publish directory and fix if found
    if [[ -d "publish" ]]; then
        echo -e "${YELLOW}⚠️  Found nested publish directory, fixing deployment structure...${NC}"
        
        # Move all files from nested publish to current level
        if [[ -n "$(ls -A publish/ 2>/dev/null)" ]]; then
            mv publish/* . 2>/dev/null || true
            rmdir publish 2>/dev/null || true
            echo -e "${BLUE}  • Fixed nested publish directory structure${NC}"
        fi
    fi
    
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
        # Check if index.html is already in root (as it should be)
        if [[ -f "index.html" ]]; then
            echo -e "${GREEN}✅ index.html found in root directory${NC}"
        else
            echo -e "${RED}❌ index.html not found in publish output${NC}"
        fi
    fi
    
    # Remove any Linux executable files that might cause issues
    if [[ -f "mTLS.Client" ]]; then
        rm -f "mTLS.Client"
        echo -e "${BLUE}  • Removed Linux executable (keeping only .dll)${NC}"
    fi
    
    # List contents for verification
    echo -e "${BLUE}📁 Package contents:${NC}"
    ls -la | head -10
    
    # Verify certificates are included
    if [[ -d "Certs" ]]; then
        echo -e "${BLUE}📄 Certificate files included:${NC}"
        ls -la Certs/ | head -5
    fi
    
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
        # Try using PowerShell on Windows/WSL
        if command -v powershell.exe &> /dev/null || [[ -n "$WSL_DISTRO_NAME" ]] || [[ "$OS" == "Windows_NT" ]]; then
            echo -e "${YELLOW}⚠️  Using PowerShell fallback for ZIP creation${NC}"
            # Convert Unix path to Windows path for PowerShell
            WIN_PATH=$(wslpath -w "$(pwd)" 2>/dev/null || pwd)
            WIN_ZIP_PATH=$(wslpath -w "$DEPLOYMENT_ZIP" 2>/dev/null || echo "$DEPLOYMENT_ZIP")
            powershell.exe -Command "Compress-Archive -Path '$WIN_PATH\\*' -DestinationPath '$WIN_ZIP_PATH' -Force"
            echo -e "${BLUE}📦 Created ZIP package with PowerShell${NC}"
        else
            echo -e "${RED}❌ No ZIP utility found. Please install zip or 7z${NC}"
            echo -e "${YELLOW}💡 To install zip on Ubuntu WSL: sudo apt update && sudo apt install zip${NC}"
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
    
    # Update deployment info without jq
    CURRENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    # Check if already has client deployment info
    if grep -q "ClientDeploymentStatus" deployment-info.json; then
        # Update existing entries
        sed -i "s/\"ClientDeploymentTimestamp\": \"[^\"]*\"/\"ClientDeploymentTimestamp\": \"$CURRENT_TIMESTAMP\"/" deployment-info.json
        sed -i 's/"ClientStatus": "[^"]*"/"ClientStatus": "Running"/' deployment-info.json
        sed -i 's/"ClientDeploymentStatus": "[^"]*"/"ClientDeploymentStatus": "Client Deployed"/' deployment-info.json
        sed -i 's/"DeploymentStatus": "[^"]*"/"DeploymentStatus": "Completed"/' deployment-info.json
    else
        # Add new fields
        sed 's/}$/,/' deployment-info.json > deployment-info-temp.json
        cat >> deployment-info-temp.json << EOF
  "ClientStatus": "Running",
  "ClientDeploymentStatus": "Client Deployed",
  "ClientDeploymentTimestamp": "$CURRENT_TIMESTAMP",
  "DeploymentStatus": "Completed"
}
EOF
        mv deployment-info-temp.json deployment-info.json
    fi
    
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
    prepare_deployment_files
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