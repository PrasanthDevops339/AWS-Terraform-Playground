#!/bin/bash

# Blue/Green Deployment Script for ECS with CodeDeploy
# This script automates the deployment process using AWS CLI

set -e

# Configuration
PROJECT_NAME="webapp-bg"
AWS_REGION="us-west-2"
CLUSTER_NAME="${PROJECT_NAME}-cluster"
SERVICE_NAME="${PROJECT_NAME}-web_app"
APP_NAME="${PROJECT_NAME}-web_app-codedeploy"
DEPLOYMENT_GROUP="${PROJECT_NAME}-web_app-dg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Function to check if required tools are installed
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

# Function to get current task definition
get_current_task_definition() {
    print_status "Getting current task definition..."
    
    CURRENT_TASK_DEF=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --region "$AWS_REGION" \
        --query 'services[0].taskDefinition' \
        --output text)
    
    if [ "$CURRENT_TASK_DEF" = "None" ]; then
        print_error "Could not retrieve current task definition"
        exit 1
    fi
    
    print_status "Current task definition: $CURRENT_TASK_DEF"
}

# Function to create new task definition
create_new_task_definition() {
    local new_image=$1
    local new_tag=$2
    
    print_status "Creating new task definition with image: $new_image:$new_tag"
    
    # Get the current task definition
    TASK_DEF_JSON=$(aws ecs describe-task-definition \
        --task-definition "$CURRENT_TASK_DEF" \
        --region "$AWS_REGION" \
        --query 'taskDefinition')
    
    # Update the image in the task definition
    NEW_TASK_DEF_JSON=$(echo "$TASK_DEF_JSON" | jq --arg image "$new_image:$new_tag" '
        .containerDefinitions[0].image = $image |
        del(.taskDefinitionArn) |
        del(.revision) |
        del(.status) |
        del(.requiresAttributes) |
        del(.placementConstraints) |
        del(.compatibilities) |
        del(.registeredAt) |
        del(.registeredBy)
    ')
    
    # Register the new task definition
    NEW_TASK_DEF_ARN=$(echo "$NEW_TASK_DEF_JSON" | aws ecs register-task-definition \
        --region "$AWS_REGION" \
        --cli-input-json file:///dev/stdin \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    print_status "New task definition created: $NEW_TASK_DEF_ARN"
}

# Function to create appspec.yaml for CodeDeploy
create_appspec() {
    print_status "Creating appspec.yaml for CodeDeploy..."
    
    cat > appspec.yaml << EOF
version: 0.0
Resources:
  - TargetService:
      Type: AWS::ECS::Service
      Properties:
        TaskDefinition: "$NEW_TASK_DEF_ARN"
        LoadBalancerInfo:
          ContainerName: "web-application"
          ContainerPort: 80
        PlatformVersion: "LATEST"
Hooks:
  - BeforeInstall: "LambdaFunctionToValidateBeforeInstall"
  - AfterInstall: "LambdaFunctionToValidateAfterTrafficShift"
  - AfterAllowTestTraffic: "LambdaFunctionToValidateAfterTestTrafficStarts"
  - BeforeAllowTraffic: "LambdaFunctionToValidateBeforeAllowingProductionTraffic"
  - AfterAllowTraffic: "LambdaFunctionToValidateAfterAllowingProductionTraffic"
EOF
    
    print_status "appspec.yaml created successfully"
}

# Function to start CodeDeploy deployment
start_deployment() {
    print_status "Starting CodeDeploy deployment..."
    
    # Create deployment
    DEPLOYMENT_ID=$(aws deploy create-deployment \
        --application-name "$APP_NAME" \
        --deployment-group-name "$DEPLOYMENT_GROUP" \
        --deployment-config-name "CodeDeployDefault.ECSAllAtOnceBlueGreen" \
        --description "Blue/Green deployment for $SERVICE_NAME" \
        --region "$AWS_REGION" \
        --query 'deploymentId' \
        --output text)
    
    print_status "Deployment started with ID: $DEPLOYMENT_ID"
    
    # Monitor deployment
    monitor_deployment "$DEPLOYMENT_ID"
}

# Function to monitor deployment status
monitor_deployment() {
    local deployment_id=$1
    
    print_status "Monitoring deployment: $deployment_id"
    
    while true; do
        DEPLOYMENT_STATUS=$(aws deploy get-deployment \
            --deployment-id "$deployment_id" \
            --region "$AWS_REGION" \
            --query 'deploymentInfo.status' \
            --output text)
        
        case $DEPLOYMENT_STATUS in
            "Created"|"Queued"|"InProgress")
                print_status "Deployment status: $DEPLOYMENT_STATUS"
                sleep 30
                ;;
            "Succeeded")
                print_status "Deployment completed successfully! ✅"
                break
                ;;
            "Failed"|"Stopped")
                print_error "Deployment failed with status: $DEPLOYMENT_STATUS ❌"
                
                # Get failure details
                aws deploy get-deployment \
                    --deployment-id "$deployment_id" \
                    --region "$AWS_REGION" \
                    --query 'deploymentInfo.errorInformation' \
                    --output table
                exit 1
                ;;
            *)
                print_warning "Unknown deployment status: $DEPLOYMENT_STATUS"
                sleep 30
                ;;
        esac
    done
}

# Function to rollback deployment
rollback_deployment() {
    local deployment_id=$1
    
    print_warning "Rolling back deployment: $deployment_id"
    
    aws deploy stop-deployment \
        --deployment-id "$deployment_id" \
        --auto-rollback-enabled \
        --region "$AWS_REGION"
    
    print_status "Rollback initiated"
}

# Function to show help
show_help() {
    cat << EOF
Blue/Green Deployment Script for ECS with CodeDeploy

Usage: $0 [OPTIONS] COMMAND

Commands:
    deploy IMAGE TAG    Deploy new version with specified image and tag
    rollback ID         Rollback deployment with specified ID
    status ID          Check deployment status
    help               Show this help message

Options:
    -r, --region       AWS region (default: us-west-2)
    -p, --project      Project name (default: webapp-bg)

Examples:
    $0 deploy nginx latest
    $0 deploy myapp/webapp v2.0.0
    $0 rollback d-ABCDEF123456
    $0 status d-ABCDEF123456

EOF
}

# Main function
main() {
    case "${1:-}" in
        "deploy")
            if [ $# -ne 3 ]; then
                print_error "Usage: $0 deploy IMAGE TAG"
                exit 1
            fi
            
            check_prerequisites
            get_current_task_definition
            create_new_task_definition "$2" "$3"
            create_appspec
            start_deployment
            ;;
        "rollback")
            if [ $# -ne 2 ]; then
                print_error "Usage: $0 rollback DEPLOYMENT_ID"
                exit 1
            fi
            
            check_prerequisites
            rollback_deployment "$2"
            ;;
        "status")
            if [ $# -ne 2 ]; then
                print_error "Usage: $0 status DEPLOYMENT_ID"
                exit 1
            fi
            
            check_prerequisites
            monitor_deployment "$2"
            ;;
        "help"|"--help"|"-h"|"")
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