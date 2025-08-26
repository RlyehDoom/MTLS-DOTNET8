#!/bin/bash
# =============================================================================
# Script: deploy-complete.sh
# Description: Complete mTLS deployment orchestration script
# Usage: ./deploy-complete.sh [options]
# =============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default values
SKIP_RESOURCES=false
SKIP_CONFIG=false
SKIP_SERVER=false
SKIP_CLIENT=false
SKIP_VERIFY=false
INTERACTIVE=true

# Function to display usage
show_usage() {
    echo -e "${BLUE}mTLS Complete Deployment Script${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 [options]"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  -h, --help              Show this help message"
    echo "  -y, --yes               Non-interactive mode (use defaults)"
    echo "  --skip-resources        Skip Azure resources creation"
    echo "  --skip-config           Skip mTLS configuration"
    echo "  --skip-server           Skip server deployment"
    echo "  --skip-client           Skip client deployment"
    echo "  --skip-verify           Skip deployment verification"
    echo ""
    echo -e "${YELLOW}Environment Variables:${NC}"
    echo "  RESOURCE_GROUP          Azure resource group name"
    echo "  LOCATION                Azure region"
    echo "  SERVER_APP_NAME         Server application name"
    echo "  CLIENT_APP_NAME         Client application name"
    echo "  SERVER_CERT_THUMBPRINT  Server certificate thumbprint"
    echo "  CA_CERT_THUMBPRINT      CA certificate thumbprint"
    echo "  CLIENT_CERT_THUMBPRINT  Client certificate thumbprint"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0                      # Interactive deployment"
    echo "  $0 -y                   # Non-interactive with defaults"
    echo "  $0 --skip-resources     # Skip resource creation"
    echo "  $0 --skip-verify        # Deploy without verification"
    echo ""
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -y|--yes)
                INTERACTIVE=false
                shift
                ;;
            --skip-resources)
                SKIP_RESOURCES=true
                shift
                ;;
            --skip-config)
                SKIP_CONFIG=true
                shift
                ;;
            --skip-server)
                SKIP_SERVER=true
                shift
                ;;
            --skip-client)
                SKIP_CLIENT=true
                shift
                ;;
            --skip-verify)
                SKIP_VERIFY=true
                shift
                ;;
            *)
                echo -e "${RED}❌ Unknown option: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to check if all required scripts exist
check_scripts() {
    local scripts=(
        "01-create-azure-resources.sh"
        "02-configure-mtls.sh"
        "03-deploy-server.sh"
        "04-deploy-client.sh"
        "05-verify-deployment.sh"
    )
    
    echo -e "${YELLOW}📋 Checking deployment scripts...${NC}"
    
    for script in "${scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            echo -e "${RED}❌ Missing script: $script${NC}"
            exit 1
        fi
        
        if [[ ! -r "$script" ]]; then
            echo -e "${RED}❌ Script $script is not readable${NC}"
            exit 1
        fi
    done
    
    echo -e "${GREEN}✅ All deployment scripts found${NC}"
}

# Function to display deployment plan
show_deployment_plan() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}              DEPLOYMENT PLAN${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${CYAN}Deployment Steps:${NC}"
    
    if [[ "$SKIP_RESOURCES" == "false" ]]; then
        echo -e "  ${GREEN}✓${NC} 1. Create Azure Resources"
    else
        echo -e "  ${YELLOW}⊘${NC} 1. Create Azure Resources (SKIPPED)"
    fi
    
    if [[ "$SKIP_CONFIG" == "false" ]]; then
        echo -e "  ${GREEN}✓${NC} 2. Configure mTLS Settings"
    else
        echo -e "  ${YELLOW}⊘${NC} 2. Configure mTLS Settings (SKIPPED)"
    fi
    
    if [[ "$SKIP_SERVER" == "false" ]]; then
        echo -e "  ${GREEN}✓${NC} 3. Deploy Server Application"
    else
        echo -e "  ${YELLOW}⊘${NC} 3. Deploy Server Application (SKIPPED)"
    fi
    
    if [[ "$SKIP_CLIENT" == "false" ]]; then
        echo -e "  ${GREEN}✓${NC} 4. Deploy Client Application"
    else
        echo -e "  ${YELLOW}⊘${NC} 4. Deploy Client Application (SKIPPED)"
    fi
    
    if [[ "$SKIP_VERIFY" == "false" ]]; then
        echo -e "  ${GREEN}✓${NC} 5. Verify Deployment"
    else
        echo -e "  ${YELLOW}⊘${NC} 5. Verify Deployment (SKIPPED)"
    fi
    
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo -e "  Resource Group: ${CYAN}${RESOURCE_GROUP:-rg-mtls-demo}${NC}"
    echo -e "  Location: ${CYAN}${LOCATION:-eastus}${NC}"
    echo -e "  Interactive Mode: ${CYAN}$INTERACTIVE${NC}"
    echo ""
}

# Function to confirm deployment
confirm_deployment() {
    if [[ "$INTERACTIVE" == "true" ]]; then
        echo -e "${YELLOW}Do you want to continue with this deployment plan? (y/N):${NC}"
        read -r confirmation
        
        if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Deployment cancelled by user.${NC}"
            exit 0
        fi
    fi
}

# Function to execute deployment step with error handling
execute_step() {
    local step_name="$1"
    local script_name="$2"
    local step_number="$3"
    
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}STEP $step_number: $step_name${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
    echo ""
    
    local start_time=$(date +%s)
    
    if NON_INTERACTIVE=true bash "$script_name"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "${GREEN}✅ Step $step_number completed successfully in ${duration}s${NC}"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "${RED}❌ Step $step_number failed after ${duration}s${NC}"
        echo -e "${RED}   Script: $script_name${NC}"
        echo -e "${RED}   Step: $step_name${NC}"
        
        if [[ "$INTERACTIVE" == "true" ]]; then
            echo ""
            echo -e "${YELLOW}Do you want to continue with the remaining steps? (y/N):${NC}"
            read -r continue_confirmation
            
            if [[ "$continue_confirmation" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}⚠️  Continuing deployment despite failure...${NC}"
                return 1
            else
                echo -e "${RED}Deployment stopped due to failure.${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Deployment stopped due to failure in non-interactive mode.${NC}"
            exit 1
        fi
    fi
}

# Function to run the complete deployment
run_deployment() {
    local start_time=$(date +%s)
    local failed_steps=0
    
    echo -e "${GREEN}🚀 Starting complete mTLS deployment...${NC}"
    
    # Step 1: Create Azure Resources
    if [[ "$SKIP_RESOURCES" == "false" ]]; then
        if ! execute_step "Create Azure Resources" "01-create-azure-resources.sh" "1"; then
            ((failed_steps++))
        fi
    fi
    
    # Step 2: Configure mTLS
    if [[ "$SKIP_CONFIG" == "false" ]]; then
        if ! execute_step "Configure mTLS Settings" "02-configure-mtls.sh" "2"; then
            ((failed_steps++))
        fi
    fi
    
    # Step 3: Deploy Server
    if [[ "$SKIP_SERVER" == "false" ]]; then
        if ! execute_step "Deploy Server Application" "03-deploy-server.sh" "3"; then
            ((failed_steps++))
        fi
    fi
    
    # Step 4: Deploy Client
    if [[ "$SKIP_CLIENT" == "false" ]]; then
        if ! execute_step "Deploy Client Application" "04-deploy-client.sh" "4"; then
            ((failed_steps++))
        fi
    fi
    
    # Step 5: Verify Deployment
    if [[ "$SKIP_VERIFY" == "false" ]]; then
        if ! execute_step "Verify Deployment" "05-verify-deployment.sh" "5"; then
            ((failed_steps++))
        fi
    fi
    
    # Calculate total deployment time
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    local minutes=$((total_duration / 60))
    local seconds=$((total_duration % 60))
    
    # Display final results
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}           DEPLOYMENT COMPLETED${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
    echo ""
    
    if [[ $failed_steps -eq 0 ]]; then
        echo -e "${GREEN}🎉 All deployment steps completed successfully!${NC}"
        echo -e "${GREEN}   Total time: ${minutes}m ${seconds}s${NC}"
    else
        echo -e "${YELLOW}⚠️  Deployment completed with $failed_steps failed step(s)${NC}"
        echo -e "${YELLOW}   Total time: ${minutes}m ${seconds}s${NC}"
        echo -e "${YELLOW}   Please review the failed steps and fix any issues${NC}"
    fi
    
    # Show final URLs if deployment info exists
    if [[ -f "deployment-info.json" ]]; then
        local server_url=$(grep '"ServerUrl"' deployment-info.json | sed 's/.*: *"\([^"]*\)".*/\1/' || echo "N/A")
        local client_url=$(grep '"ClientUrl"' deployment-info.json | sed 's/.*: *"\([^"]*\)".*/\1/' || echo "N/A")
        
        echo ""
        echo -e "${CYAN}🔗 Application URLs:${NC}"
        echo -e "  • Server: ${YELLOW}$server_url${NC}"
        echo -e "  • Client: ${YELLOW}$client_url${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}📋 Next Steps:${NC}"
    echo -e "  1. Test your applications manually"
    echo -e "  2. Upload certificates if not done yet"
    echo -e "  3. Configure monitoring and alerting"
    echo -e "  4. Document your deployment"
    echo ""
}

# Main execution
main() {
    echo -e "${GREEN}🔐 mTLS Complete Deployment Script${NC}"
    echo ""
    
    parse_arguments "$@"
    check_scripts
    show_deployment_plan
    confirm_deployment
    run_deployment
}

# Run main function with all arguments
main "$@"