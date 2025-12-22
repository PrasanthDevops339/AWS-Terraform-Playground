#!/bin/bash

# Service Connect TLS Testing Script
# This script helps test the TLS-enabled service connectivity

set -e

# Configuration
PROJECT_NAME="secure-microservices"
AWS_REGION="us-west-2"
CLUSTER_NAME="${PROJECT_NAME}-cluster"
NAMESPACE="secure.local"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[HEADER]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_status "Prerequisites check passed!"
}

# Function to get cluster status
get_cluster_status() {
    print_header "Checking ECS Cluster Status"
    
    CLUSTER_STATUS=$(aws ecs describe-clusters \
        --clusters "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'clusters[0].status' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
        print_status "✅ Cluster '$CLUSTER_NAME' is active"
    elif [ "$CLUSTER_STATUS" = "NOT_FOUND" ]; then
        print_error "❌ Cluster '$CLUSTER_NAME' not found"
        return 1
    else
        print_warning "⚠️ Cluster '$CLUSTER_NAME' status: $CLUSTER_STATUS"
    fi
}

# Function to get service status
get_services_status() {
    print_header "Checking ECS Services Status"
    
    SERVICES=$(aws ecs list-services \
        --cluster "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'serviceArns' \
        --output text)
    
    if [ -z "$SERVICES" ] || [ "$SERVICES" = "None" ]; then
        print_error "❌ No services found in cluster '$CLUSTER_NAME'"
        return 1
    fi
    
    # Get service details
    aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services $SERVICES \
        --region "$AWS_REGION" \
        --query 'services[].[serviceName,status,runningCount,desiredCount,taskDefinition]' \
        --output table
}

# Function to test service connectivity
test_service_connectivity() {
    print_header "Testing Service Connect Connectivity"
    
    # Get one of the running tasks
    TASK_ARN=$(aws ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'taskArns[0]' \
        --output text)
    
    if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
        print_error "❌ No running tasks found"
        return 1
    fi
    
    print_status "Found task: $TASK_ARN"
    
    # Test DNS resolution within the service connect namespace
    print_status "Testing DNS resolution for service connect services..."
    
    # Test secure-api service
    print_status "Testing secure-api.${NAMESPACE} resolution..."
    aws ecs execute-command \
        --cluster "$CLUSTER_NAME" \
        --task "$TASK_ARN" \
        --container "client-app" \
        --interactive \
        --command "nslookup secure-api.${NAMESPACE}" \
        --region "$AWS_REGION" || print_warning "DNS resolution test failed (this might be expected if ECS Exec is not enabled)"
    
    # Test database service
    print_status "Testing postgres-db.${NAMESPACE} resolution..."
    aws ecs execute-command \
        --cluster "$CLUSTER_NAME" \
        --task "$TASK_ARN" \
        --container "client-app" \
        --interactive \
        --command "nslookup postgres-db.${NAMESPACE}" \
        --region "$AWS_REGION" || print_warning "DNS resolution test failed (this might be expected if ECS Exec is not enabled)"
}

# Function to check certificate authority status
check_certificate_authority() {
    print_header "Checking Certificate Authority Status"
    
    CA_ARN=$(aws acm-pca list-certificate-authorities \
        --region "$AWS_REGION" \
        --query "CertificateAuthorities[?contains(Arn, '${PROJECT_NAME}')].Arn" \
        --output text)
    
    if [ -z "$CA_ARN" ]; then
        print_error "❌ Certificate Authority not found"
        return 1
    fi
    
    print_status "Found Certificate Authority: $CA_ARN"
    
    CA_STATUS=$(aws acm-pca describe-certificate-authority \
        --certificate-authority-arn "$CA_ARN" \
        --region "$AWS_REGION" \
        --query 'CertificateAuthority.Status' \
        --output text)
    
    if [ "$CA_STATUS" = "ACTIVE" ]; then
        print_status "✅ Certificate Authority is active"
    else
        print_warning "⚠️ Certificate Authority status: $CA_STATUS"
    fi
}

# Function to check KMS key status
check_kms_key() {
    print_header "Checking KMS Key Status"
    
    KEY_ALIAS="alias/${PROJECT_NAME}-service-connect-tls"
    
    KEY_ARN=$(aws kms describe-key \
        --key-id "$KEY_ALIAS" \
        --region "$AWS_REGION" \
        --query 'KeyMetadata.Arn' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$KEY_ARN" = "NOT_FOUND" ]; then
        print_error "❌ KMS key not found: $KEY_ALIAS"
        return 1
    fi
    
    print_status "✅ KMS key found: $KEY_ARN"
    
    KEY_STATE=$(aws kms describe-key \
        --key-id "$KEY_ALIAS" \
        --region "$AWS_REGION" \
        --query 'KeyMetadata.KeyState' \
        --output text)
    
    if [ "$KEY_STATE" = "Enabled" ]; then
        print_status "✅ KMS key is enabled"
    else
        print_warning "⚠️ KMS key state: $KEY_STATE"
    fi
}

# Function to check service discovery namespace
check_service_discovery() {
    print_header "Checking Service Discovery Namespace"
    
    NAMESPACE_ID=$(aws servicediscovery list-namespaces \
        --region "$AWS_REGION" \
        --query "Namespaces[?Name=='${NAMESPACE}'].Id" \
        --output text)
    
    if [ -z "$NAMESPACE_ID" ]; then
        print_error "❌ Service discovery namespace '$NAMESPACE' not found"
        return 1
    fi
    
    print_status "✅ Service discovery namespace found: $NAMESPACE (ID: $NAMESPACE_ID)"
    
    # List services in the namespace
    aws servicediscovery list-services \
        --filters Name="NAMESPACE_ID",Values="$NAMESPACE_ID",Condition="EQ" \
        --region "$AWS_REGION" \
        --query 'Services[].[Name,Id,InstanceCount]' \
        --output table
}

# Function to check CloudWatch logs
check_cloudwatch_logs() {
    print_header "Checking CloudWatch Logs"
    
    LOG_GROUPS=(
        "/aws/ecs/service-connect"
        "/aws/ecs/secure-api"
        "/aws/ecs/client-service"
        "/aws/ecs/database"
    )
    
    for LOG_GROUP in "${LOG_GROUPS[@]}"; do
        LOG_STREAMS=$(aws logs describe-log-streams \
            --log-group-name "$LOG_GROUP" \
            --region "$AWS_REGION" \
            --query 'logStreams[0].logStreamName' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$LOG_STREAMS" != "NOT_FOUND" ] && [ "$LOG_STREAMS" != "None" ]; then
            print_status "✅ Log group '$LOG_GROUP' has active streams"
        else
            print_warning "⚠️ No log streams found in '$LOG_GROUP'"
        fi
    done
}

# Function to show service endpoints
show_service_endpoints() {
    print_header "Service Endpoints"
    
    cat << EOF

Service Connect Endpoints within the cluster:
┌─────────────────┬──────────────────────────────────────────┐
│ Service         │ Endpoint                                 │
├─────────────────┼──────────────────────────────────────────┤
│ Secure API      │ https://secure-api.${NAMESPACE}:8443     │
│ Client App      │ http://client-app.${NAMESPACE}:80        │
│ Database        │ postgres://postgres-db.${NAMESPACE}:5432 │
└─────────────────┴──────────────────────────────────────────┘

Note: These endpoints are only accessible from within the ECS cluster
      using Service Connect networking.

EOF
}

# Function to run all health checks
run_health_checks() {
    print_header "Running Health Checks for Service Connect TLS Setup"
    
    local failed_checks=0
    
    check_prerequisites || ((failed_checks++))
    get_cluster_status || ((failed_checks++))
    get_services_status || ((failed_checks++))
    check_certificate_authority || ((failed_checks++))
    check_kms_key || ((failed_checks++))
    check_service_discovery || ((failed_checks++))
    check_cloudwatch_logs
    
    if [ $failed_checks -eq 0 ]; then
        print_status "✅ All health checks passed!"
        show_service_endpoints
    else
        print_error "❌ $failed_checks health check(s) failed"
        return 1
    fi
}

# Function to show help
show_help() {
    cat << EOF
Service Connect TLS Testing Script

Usage: $0 [COMMAND]

Commands:
    health          Run all health checks
    cluster         Check cluster status
    services        Check services status
    ca              Check certificate authority status
    kms             Check KMS key status
    discovery       Check service discovery status
    logs            Check CloudWatch logs
    connectivity    Test service connectivity (requires ECS Exec)
    endpoints       Show service endpoints
    help            Show this help message

Examples:
    $0 health
    $0 cluster
    $0 services
    $0 connectivity

EOF
}

# Main function
main() {
    case "${1:-health}" in
        "health")
            run_health_checks
            ;;
        "cluster")
            check_prerequisites
            get_cluster_status
            ;;
        "services")
            check_prerequisites
            get_services_status
            ;;
        "ca")
            check_prerequisites
            check_certificate_authority
            ;;
        "kms")
            check_prerequisites
            check_kms_key
            ;;
        "discovery")
            check_prerequisites
            check_service_discovery
            ;;
        "logs")
            check_prerequisites
            check_cloudwatch_logs
            ;;
        "connectivity")
            check_prerequisites
            test_service_connectivity
            ;;
        "endpoints")
            show_service_endpoints
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"