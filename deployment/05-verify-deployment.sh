#!/bin/bash
# =============================================================================
# Script: 05-verify-deployment.sh
# Description: Verify mTLS deployment and test all functionality
# Prerequisites: Complete deployment (server and client)
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

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to load deployment info
load_deployment_info() {
    if [[ ! -f "deployment-info.json" ]]; then
        echo -e "${RED}❌ deployment-info.json not found. Please run deployment scripts first.${NC}"
        exit 1
    fi
    
    RESOURCE_GROUP=$(cat deployment-info.json | jq -r '.ResourceGroup')
    SERVER_APP_NAME=$(cat deployment-info.json | jq -r '.ServerAppName')
    CLIENT_APP_NAME=$(cat deployment-info.json | jq -r '.ClientAppName')
    SERVER_URL=$(cat deployment-info.json | jq -r '.ServerUrl')
    CLIENT_URL=$(cat deployment-info.json | jq -r '.ClientUrl')
    SERVER_CERT_THUMBPRINT=$(cat deployment-info.json | jq -r '.ServerCertThumbprint // "N/A"')
    CA_CERT_THUMBPRINT=$(cat deployment-info.json | jq -r '.CACertThumbprint // "N/A"')
    CLIENT_CERT_THUMBPRINT=$(cat deployment-info.json | jq -r '.ClientCertThumbprint // "N/A"')
    
    echo -e "${BLUE}📋 Loaded deployment configuration:${NC}"
    echo -e "  Resource Group: ${CYAN}$RESOURCE_GROUP${NC}"
    echo -e "  Server: ${CYAN}$SERVER_APP_NAME${NC} (${SERVER_URL})"
    echo -e "  Client: ${CYAN}$CLIENT_APP_NAME${NC} (${CLIENT_URL})"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
    
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}❌ curl is not installed${NC}"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}❌ jq is not installed${NC}"
        exit 1
    fi
    
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI is not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    ((TOTAL_TESTS++))
    
    echo -e "${BLUE}  Testing: $test_name${NC}"
    
    if eval "$test_command"; then
        if [[ "$expected_result" == "pass" ]]; then
            echo -e "${GREEN}  ✅ $test_name - PASSED${NC}"
            ((PASSED_TESTS++))
            return 0
        else
            echo -e "${YELLOW}  ⚠️  $test_name - UNEXPECTED SUCCESS${NC}"
            ((FAILED_TESTS++))
            return 1
        fi
    else
        if [[ "$expected_result" == "fail" ]]; then
            echo -e "${GREEN}  ✅ $test_name - EXPECTED FAILURE${NC}"
            ((PASSED_TESTS++))
            return 0
        else
            echo -e "${RED}  ❌ $test_name - FAILED${NC}"
            ((FAILED_TESTS++))
            return 1
        fi
    fi
}

# Function to test Azure resource status
test_azure_resources() {
    echo -e "${YELLOW}🏗️  Testing Azure Resources Status...${NC}"
    
    # Test resource group exists
    run_test "Resource Group Exists" \
        "az group show --name '$RESOURCE_GROUP' > /dev/null 2>&1" \
        "pass"
    
    # Test server app exists and is running
    run_test "Server App Exists" \
        "az webapp show --resource-group '$RESOURCE_GROUP' --name '$SERVER_APP_NAME' > /dev/null 2>&1" \
        "pass"
    
    # Test client app exists and is running
    run_test "Client App Exists" \
        "az webapp show --resource-group '$RESOURCE_GROUP' --name '$CLIENT_APP_NAME' > /dev/null 2>&1" \
        "pass"
    
    echo ""
}

# Function to test basic connectivity
test_basic_connectivity() {
    echo -e "${YELLOW}🌐 Testing Basic Connectivity...${NC}"
    
    # Test server health endpoint
    run_test "Server Health Check" \
        "curl -s -f -m 10 '$SERVER_URL/health' > /dev/null" \
        "pass"
    
    # Test server weather endpoint
    run_test "Server Weather API" \
        "curl -s -f -m 10 '$SERVER_URL/weatherforecast' > /dev/null" \
        "pass"
    
    # Test client home endpoint
    run_test "Client Home Page" \
        "curl -s -f -m 10 '$CLIENT_URL/' > /dev/null" \
        "pass"
    
    # Test client cert-info endpoint
    run_test "Client Certificate Info" \
        "curl -s -f -m 10 '$CLIENT_URL/cert-info' > /dev/null" \
        "pass"
    
    echo ""
}

# Function to test HTTP/2 support
test_http2_support() {
    echo -e "${YELLOW}🚀 Testing HTTP/2 Support...${NC}"
    
    # Test server HTTP/2
    run_test "Server HTTP/2 Support" \
        "curl -s -I --http2 -m 10 '$SERVER_URL/health' | grep -i 'HTTP/2' > /dev/null" \
        "pass"
    
    # Test client HTTP/2
    run_test "Client HTTP/2 Support" \
        "curl -s -I --http2 -m 10 '$CLIENT_URL/' | grep -i 'HTTP/2' > /dev/null" \
        "pass"
    
    echo ""
}

# Function to test security headers
test_security_headers() {
    echo -e "${YELLOW}🔒 Testing Security Headers...${NC}"
    
    # Test HTTPS redirect
    run_test "Server HTTPS Redirect" \
        "curl -s -I -m 10 'http://$SERVER_APP_NAME.azurewebsites.net' | grep -i 'location.*https' > /dev/null" \
        "pass"
    
    run_test "Client HTTPS Redirect" \
        "curl -s -I -m 10 'http://$CLIENT_APP_NAME.azurewebsites.net' | grep -i 'location.*https' > /dev/null" \
        "pass"
    
    # Test security headers presence
    run_test "Server Security Headers" \
        "curl -s -I -m 10 '$SERVER_URL/health' | grep -i 'strict-transport-security' > /dev/null" \
        "pass"
    
    echo ""
}

# Function to test mTLS configuration
test_mtls_configuration() {
    echo -e "${YELLOW}🔐 Testing mTLS Configuration...${NC}"
    
    # Test that mTLS endpoint requires client certificate (should fail without cert)
    run_test "mTLS Endpoint Requires Client Cert" \
        "curl -s -f -m 10 '$SERVER_URL/mtls-test' > /dev/null" \
        "fail"
    
    # Test Azure app settings for client cert requirement
    run_test "Server Client Certificate Required" \
        "az webapp show --resource-group '$RESOURCE_GROUP' --name '$SERVER_APP_NAME' --query 'clientCertEnabled' -o tsv | grep -i true > /dev/null" \
        "pass"
    
    run_test "Server Client Certificate Mode Required" \
        "az webapp show --resource-group '$RESOURCE_GROUP' --name '$SERVER_APP_NAME' --query 'clientCertMode' -o tsv | grep -i required > /dev/null" \
        "pass"
    
    echo ""
}

# Function to test certificate configuration
test_certificate_configuration() {
    echo -e "${YELLOW}📜 Testing Certificate Configuration...${NC}"
    
    # Check if certificate thumbprints are configured
    if [[ "$SERVER_CERT_THUMBPRINT" != "N/A" && "$SERVER_CERT_THUMBPRINT" != "" ]]; then
        echo -e "${GREEN}  ✅ Server Certificate Thumbprint: $SERVER_CERT_THUMBPRINT${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Server Certificate Thumbprint not configured${NC}"
    fi
    
    if [[ "$CA_CERT_THUMBPRINT" != "N/A" && "$CA_CERT_THUMBPRINT" != "" ]]; then
        echo -e "${GREEN}  ✅ CA Certificate Thumbprint: $CA_CERT_THUMBPRINT${NC}"
    else
        echo -e "${YELLOW}  ⚠️  CA Certificate Thumbprint not configured${NC}"
    fi
    
    if [[ "$CLIENT_CERT_THUMBPRINT" != "N/A" && "$CLIENT_CERT_THUMBPRINT" != "" ]]; then
        echo -e "${GREEN}  ✅ Client Certificate Thumbprint: $CLIENT_CERT_THUMBPRINT${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Client Certificate Thumbprint not configured${NC}"
    fi
    
    echo ""
}

# Function to test application settings
test_application_settings() {
    echo -e "${YELLOW}⚙️  Testing Application Settings...${NC}"
    
    # Check server app settings
    run_test "Server Environment Setting" \
        "az webapp config appsettings list --resource-group '$RESOURCE_GROUP' --name '$SERVER_APP_NAME' --query \"[?name=='ASPNETCORE_ENVIRONMENT'].value\" -o tsv | grep Production > /dev/null" \
        "pass"
    
    # Check client app settings
    run_test "Client Environment Setting" \
        "az webapp config appsettings list --resource-group '$RESOURCE_GROUP' --name '$CLIENT_APP_NAME' --query \"[?name=='ASPNETCORE_ENVIRONMENT'].value\" -o tsv | grep Production > /dev/null" \
        "pass"
    
    run_test "Client Server URL Setting" \
        "az webapp config appsettings list --resource-group '$RESOURCE_GROUP' --name '$CLIENT_APP_NAME' --query \"[?name=='ServerUrl'].value\" -o tsv | grep '$SERVER_URL' > /dev/null" \
        "pass"
    
    echo ""
}

# Function to test end-to-end mTLS communication
test_end_to_end_mtls() {
    echo -e "${YELLOW}🔄 Testing End-to-End mTLS Communication...${NC}"
    
    # Test client's ability to test server connection
    echo -e "${BLUE}  Testing client -> server mTLS communication via client app...${NC}"
    
    # Try to call the client's test-server endpoint
    if curl -s -m 30 "$CLIENT_URL/test-server" > /tmp/mtls_test_result.json 2>/dev/null; then
        if [[ -f /tmp/mtls_test_result.json ]]; then
            echo -e "${GREEN}  ✅ Client can communicate with server via mTLS${NC}"
            
            # Try to parse and display result
            if command -v jq &> /dev/null && jq . /tmp/mtls_test_result.json > /dev/null 2>&1; then
                echo -e "${CYAN}  Response details:${NC}"
                jq '.' /tmp/mtls_test_result.json 2>/dev/null || echo "  (Could not parse JSON response)"
            fi
            
            rm -f /tmp/mtls_test_result.json
            ((TOTAL_TESTS++))
            ((PASSED_TESTS++))
        else
            echo -e "${YELLOW}  ⚠️  Client responded but no valid result received${NC}"
            ((TOTAL_TESTS++))
            ((FAILED_TESTS++))
        fi
    else
        echo -e "${YELLOW}  ⚠️  Client could not establish mTLS connection with server${NC}"
        echo -e "${BLUE}     This might be expected if certificates are not properly uploaded${NC}"
        ((TOTAL_TESTS++))
        ((FAILED_TESTS++))
    fi
    
    echo ""
}

# Function to check logs for errors
check_application_logs() {
    echo -e "${YELLOW}📋 Checking Application Logs for Errors...${NC}"
    
    # Check server logs
    echo -e "${BLUE}  Checking server logs...${NC}"
    if az webapp log tail --resource-group "$RESOURCE_GROUP" --name "$SERVER_APP_NAME" --timeout 10 2>/dev/null | grep -i error > /tmp/server_errors.log 2>/dev/null; then
        if [[ -s /tmp/server_errors.log ]]; then
            echo -e "${YELLOW}  ⚠️  Found errors in server logs:${NC}"
            head -5 /tmp/server_errors.log
        else
            echo -e "${GREEN}  ✅ No errors found in server logs${NC}"
        fi
    else
        echo -e "${BLUE}  ℹ️  Could not retrieve server logs (this is normal)${NC}"
    fi
    
    # Check client logs
    echo -e "${BLUE}  Checking client logs...${NC}"
    if az webapp log tail --resource-group "$RESOURCE_GROUP" --name "$CLIENT_APP_NAME" --timeout 10 2>/dev/null | grep -i error > /tmp/client_errors.log 2>/dev/null; then
        if [[ -s /tmp/client_errors.log ]]; then
            echo -e "${YELLOW}  ⚠️  Found errors in client logs:${NC}"
            head -5 /tmp/client_errors.log
        else
            echo -e "${GREEN}  ✅ No errors found in client logs${NC}"
        fi
    else
        echo -e "${BLUE}  ℹ️  Could not retrieve client logs (this is normal)${NC}"
    fi
    
    # Cleanup
    rm -f /tmp/server_errors.log /tmp/client_errors.log
    
    echo ""
}

# Function to display comprehensive test results
display_test_results() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}           DEPLOYMENT VERIFICATION RESULTS${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
    echo ""
    
    # Calculate success rate
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    echo -e "${CYAN}📊 Test Summary:${NC}"
    echo -e "  Total Tests: ${YELLOW}$TOTAL_TESTS${NC}"
    echo -e "  Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "  Failed: ${RED}$FAILED_TESTS${NC}"
    echo -e "  Success Rate: ${YELLOW}$success_rate%${NC}"
    echo ""
    
    # Overall status
    if [[ $success_rate -ge 80 ]]; then
        echo -e "${GREEN}🎉 DEPLOYMENT STATUS: EXCELLENT${NC}"
        echo -e "${GREEN}   Your mTLS deployment is working well!${NC}"
    elif [[ $success_rate -ge 60 ]]; then
        echo -e "${YELLOW}⚠️  DEPLOYMENT STATUS: GOOD${NC}"
        echo -e "${YELLOW}   Most features are working, but some issues were found.${NC}"
    else
        echo -e "${RED}❌ DEPLOYMENT STATUS: NEEDS ATTENTION${NC}"
        echo -e "${RED}   Several issues were found that need to be addressed.${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}🔗 Application URLs:${NC}"
    echo -e "  • Server: ${CYAN}$SERVER_URL${NC}"
    echo -e "  • Client: ${CYAN}$CLIENT_URL${NC}"
    echo ""
    
    echo -e "${BLUE}🧪 Manual Testing:${NC}"
    echo -e "  • Health Check: ${YELLOW}curl $SERVER_URL/health${NC}"
    echo -e "  • Weather API: ${YELLOW}curl $SERVER_URL/weatherforecast${NC}"
    echo -e "  • Client Home: ${YELLOW}curl $CLIENT_URL/${NC}"
    echo -e "  • mTLS Test: ${YELLOW}curl $CLIENT_URL/test-server${NC}"
    echo ""
    
    if [[ "$CLIENT_CERT_THUMBPRINT" != "N/A" && "$CLIENT_CERT_THUMBPRINT" != "" ]]; then
        echo -e "${BLUE}📜 Certificate Configuration:${NC}"
        echo -e "  • Server Cert: ${YELLOW}$SERVER_CERT_THUMBPRINT${NC}"
        echo -e "  • CA Cert: ${YELLOW}$CA_CERT_THUMBPRINT${NC}"
        echo -e "  • Client Cert: ${YELLOW}$CLIENT_CERT_THUMBPRINT${NC}"
        echo ""
    fi
    
    echo -e "${BLUE}📋 Next Steps:${NC}"
    if [[ $success_rate -lt 100 ]]; then
        echo -e "  1. Review failed tests and address issues"
        echo -e "  2. Check Azure portal for certificate uploads"
        echo -e "  3. Verify certificate thumbprints match"
        echo -e "  4. Check application logs for detailed errors"
    else
        echo -e "  1. Test mTLS functionality manually"
        echo -e "  2. Implement monitoring and alerting"
        echo -e "  3. Document the deployment for your team"
    fi
    echo ""
}

# Main execution
main() {
    echo -e "${GREEN}🔍 Starting mTLS Deployment Verification...${NC}"
    echo ""
    
    check_prerequisites
    load_deployment_info
    
    test_azure_resources
    test_basic_connectivity
    test_http2_support
    test_security_headers
    test_mtls_configuration
    test_certificate_configuration
    test_application_settings
    test_end_to_end_mtls
    check_application_logs
    
    display_test_results
}

# Run main function
main "$@"