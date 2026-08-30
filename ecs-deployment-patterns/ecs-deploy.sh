#!/usr/bin/env bash
# ==============================================================================
# ECS-Native Deployment Script
# Supports: ROLLING | BLUE_GREEN | LINEAR | CANARY (July+Oct 2025 GA)
#
# Usage: ./ecs-deploy.sh
#
# Required Environment Variables:
#   ECS_CLUSTER       - ECS cluster name
#   ECS_SERVICE       - ECS service name
#   IMAGE_URI         - New container image URI (e.g. 123456.dkr.ecr.region.amazonaws.com/app:v1.2.3)
#   CONTAINER_NAME    - Container name in the task definition to update
#   DEPLOY_STRATEGY   - ROLLING | BLUE_GREEN | LINEAR | CANARY
#
# Optional Environment Variables (strategy-specific):
#   # Blue/Green
#   BG_BAKE_TIME_MINUTES         - Bake time after traffic shift (default: 5)
#
#   # Linear
#   LINEAR_STEP_PERCENT          - % traffic per step (default: 10)
#   LINEAR_STEP_BAKE_MINUTES     - Wait between steps (default: 5)
#   LINEAR_BAKE_TIME_MINUTES     - Final bake time (default: 5)
#
#   # Canary
#   CANARY_PERCENT               - % traffic to canary (default: 10)
#   CANARY_BAKE_MINUTES          - Canary bake time (default: 10)
#   CANARY_FINAL_BAKE_MINUTES    - Final bake time (default: 5)
#
#   # Common
#   CIRCUIT_BREAKER_ENABLED      - true/false (default: true)
#   CIRCUIT_BREAKER_ROLLBACK     - true/false (default: true)
#   ALARM_NAMES                  - Comma-separated CloudWatch alarm names
#   WAIT_TIMEOUT                 - Max seconds to wait for deployment (default: 900)
#   AWS_REGION                   - AWS region (default: from AWS config)
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[$(date +'%H:%M:%S')]${NC} $*"; }
ok()   { echo -e "${GREEN}[$(date +'%H:%M:%S')] ✅${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️${NC} $*"; }
err()  { echo -e "${RED}[$(date +'%H:%M:%S')] ❌${NC} $*" >&2; }

# ==============================================================================
# Validate required inputs
# ==============================================================================
: "${ECS_CLUSTER:?'ECS_CLUSTER is required'}"
: "${ECS_SERVICE:?'ECS_SERVICE is required'}"
: "${IMAGE_URI:?'IMAGE_URI is required'}"
: "${CONTAINER_NAME:?'CONTAINER_NAME is required'}"
: "${DEPLOY_STRATEGY:?'DEPLOY_STRATEGY is required (ROLLING|BLUE_GREEN|LINEAR|CANARY)'}"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-900}"
CIRCUIT_BREAKER_ENABLED="${CIRCUIT_BREAKER_ENABLED:-true}"
CIRCUIT_BREAKER_ROLLBACK="${CIRCUIT_BREAKER_ROLLBACK:-true}"
ALARM_NAMES="${ALARM_NAMES:-}"
REGION_FLAG=""
if [[ -n "${AWS_REGION:-}" ]]; then
  REGION_FLAG="--region ${AWS_REGION}"
fi

log "═══════════════════════════════════════════════════════════════"
log "  ECS-Native Deployment"
log "  Cluster:    ${ECS_CLUSTER}"
log "  Service:    ${ECS_SERVICE}"
log "  Image:      ${IMAGE_URI}"
log "  Container:  ${CONTAINER_NAME}"
log "  Strategy:   ${DEPLOY_STRATEGY}"
log "═══════════════════════════════════════════════════════════════"

# ==============================================================================
# Step 1: Get current task definition and create new revision
# ==============================================================================
log "📋 Fetching current task definition..."

CURRENT_TD_ARN=$(aws ecs describe-services \
  ${REGION_FLAG} \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --query 'services[0].taskDefinition' \
  --output text)

log "   Current task definition: ${CURRENT_TD_ARN}"

# Fetch the full task definition
TASK_DEF_JSON=$(aws ecs describe-task-definition \
  ${REGION_FLAG} \
  --task-definition "${CURRENT_TD_ARN}" \
  --query 'taskDefinition')

# Update the container image in the task definition
log "🔄 Updating container image for '${CONTAINER_NAME}'..."

NEW_TASK_DEF=$(echo "${TASK_DEF_JSON}" | \
  jq --arg CONTAINER "${CONTAINER_NAME}" \
     --arg IMAGE "${IMAGE_URI}" \
  '.containerDefinitions = [.containerDefinitions[] |
    if .name == $CONTAINER then .image = $IMAGE else . end]')

# Strip read-only fields before registering
REGISTER_INPUT=$(echo "${NEW_TASK_DEF}" | jq '{
  family: .family,
  taskRoleArn: .taskRoleArn,
  executionRoleArn: .executionRoleArn,
  networkMode: .networkMode,
  containerDefinitions: .containerDefinitions,
  volumes: .volumes,
  placementConstraints: .placementConstraints,
  requiresCompatibilities: .requiresCompatibilities,
  cpu: .cpu,
  memory: .memory,
  pidMode: .pidMode,
  ephemeralStorage: .ephemeralStorage,
  runtimePlatform: .runtimePlatform
} | with_entries(select(.value != null))')

log "📝 Registering new task definition revision..."
NEW_TD_ARN=$(aws ecs register-task-definition \
  ${REGION_FLAG} \
  --cli-input-json "${REGISTER_INPUT}" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

ok "New task definition: ${NEW_TD_ARN}"

# ==============================================================================
# Step 2: Build deployment configuration JSON based on strategy
# ==============================================================================
log "⚙️  Building deployment configuration for ${DEPLOY_STRATEGY}..."

# Base circuit breaker config
CB_JSON=$(jq -n \
  --argjson enable "${CIRCUIT_BREAKER_ENABLED}" \
  --argjson rollback "${CIRCUIT_BREAKER_ROLLBACK}" \
  '{enable: $enable, rollback: $rollback}')

# Alarms configuration
ALARMS_JSON="null"
if [[ -n "${ALARM_NAMES}" ]]; then
  ALARMS_JSON=$(echo "${ALARM_NAMES}" | tr ',' '\n' | jq -R . | jq -s '{
    alarmNames: .,
    enable: true,
    rollback: true
  }')
fi

case "${DEPLOY_STRATEGY}" in
  ROLLING)
    DEPLOY_CONFIG=$(jq -n \
      --argjson cb "${CB_JSON}" \
      --argjson alarms "${ALARMS_JSON}" \
      '{
        maximumPercent: 200,
        minimumHealthyPercent: 100,
        deploymentCircuitBreaker: $cb
      } + (if $alarms != null then {alarms: $alarms} else {} end)')
    ;;

  BLUE_GREEN)
    BG_BAKE="${BG_BAKE_TIME_MINUTES:-5}"
    DEPLOY_CONFIG=$(jq -n \
      --argjson cb "${CB_JSON}" \
      --argjson alarms "${ALARMS_JSON}" \
      --argjson bake "${BG_BAKE}" \
      '{
        strategy: "BLUE_GREEN",
        deploymentCircuitBreaker: $cb,
        bakeTimeInMinutes: $bake
      } + (if $alarms != null then {alarms: $alarms} else {} end)')
    log "   Bake time: ${BG_BAKE} min"
    ;;

  LINEAR)
    STEP_PCT="${LINEAR_STEP_PERCENT:-10}"
    STEP_BAKE="${LINEAR_STEP_BAKE_MINUTES:-5}"
    FINAL_BAKE="${LINEAR_BAKE_TIME_MINUTES:-5}"
    DEPLOY_CONFIG=$(jq -n \
      --argjson cb "${CB_JSON}" \
      --argjson alarms "${ALARMS_JSON}" \
      --argjson step_pct "${STEP_PCT}" \
      --argjson step_bake "${STEP_BAKE}" \
      --argjson final_bake "${FINAL_BAKE}" \
      '{
        strategy: "LINEAR",
        deploymentCircuitBreaker: $cb,
        bakeTimeInMinutes: $final_bake,
        linearConfiguration: {
          stepPercent: $step_pct,
          stepBakeTimeInMinutes: $step_bake
        }
      } + (if $alarms != null then {alarms: $alarms} else {} end)')
    log "   Step: ${STEP_PCT}% every ${STEP_BAKE}min, final bake: ${FINAL_BAKE}min"
    ;;

  CANARY)
    CANARY_PCT="${CANARY_PERCENT:-10}"
    CANARY_BAKE="${CANARY_BAKE_MINUTES:-10}"
    FINAL_BAKE="${CANARY_FINAL_BAKE_MINUTES:-5}"
    DEPLOY_CONFIG=$(jq -n \
      --argjson cb "${CB_JSON}" \
      --argjson alarms "${ALARMS_JSON}" \
      --argjson pct "${CANARY_PCT}" \
      --argjson bake "${CANARY_BAKE}" \
      --argjson final_bake "${FINAL_BAKE}" \
      '{
        strategy: "CANARY",
        deploymentCircuitBreaker: $cb,
        bakeTimeInMinutes: $final_bake,
        canaryConfiguration: {
          canaryPercent: $pct,
          canaryBakeTimeInMinutes: $bake
        }
      } + (if $alarms != null then {alarms: $alarms} else {} end)')
    log "   Canary: ${CANARY_PCT}%, bake: ${CANARY_BAKE}min, final: ${FINAL_BAKE}min"
    ;;

  *)
    err "Unknown strategy: ${DEPLOY_STRATEGY}. Use ROLLING|BLUE_GREEN|LINEAR|CANARY"
    exit 1
    ;;
esac

ok "Deployment configuration built"

# ==============================================================================
# Step 3: Update the ECS service to trigger deployment
# ==============================================================================
log "🚀 Triggering ECS deployment..."

aws ecs update-service \
  ${REGION_FLAG} \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --task-definition "${NEW_TD_ARN}" \
  --deployment-configuration "${DEPLOY_CONFIG}" \
  --force-new-deployment \
  --query 'service.deployments[0].{status:status,desired:desiredCount,running:runningCount,rolloutState:rolloutState}' \
  --output table

ok "Deployment triggered successfully"

# ==============================================================================
# Step 4: Wait for deployment to stabilise
# ==============================================================================
log "⏳ Waiting for service to stabilise (timeout: ${WAIT_TIMEOUT}s)..."

SECONDS=0
LAST_STATUS=""
while (( SECONDS < WAIT_TIMEOUT )); do
  # Fetch deployment status
  DEPLOY_INFO=$(aws ecs describe-services \
    ${REGION_FLAG} \
    --cluster "${ECS_CLUSTER}" \
    --services "${ECS_SERVICE}" \
    --query 'services[0].deployments[0].{
      status: status,
      rolloutState: rolloutState,
      desiredCount: desiredCount,
      runningCount: runningCount,
      pendingCount: pendingCount,
      failedTasks: failedTasks
    }' --output json)

  ROLLOUT_STATE=$(echo "${DEPLOY_INFO}" | jq -r '.rolloutState // "UNKNOWN"')
  RUNNING=$(echo "${DEPLOY_INFO}" | jq -r '.runningCount // 0')
  DESIRED=$(echo "${DEPLOY_INFO}" | jq -r '.desiredCount // 0')
  FAILED=$(echo "${DEPLOY_INFO}" | jq -r '.failedTasks // 0')

  STATUS_LINE="   [${SECONDS}s] State: ${ROLLOUT_STATE} | Running: ${RUNNING}/${DESIRED} | Failed: ${FAILED}"

  if [[ "${STATUS_LINE}" != "${LAST_STATUS}" ]]; then
    log "${STATUS_LINE}"
    LAST_STATUS="${STATUS_LINE}"
  fi

  case "${ROLLOUT_STATE}" in
    COMPLETED)
      ok "═══════════════════════════════════════════════════════════════"
      ok "  Deployment COMPLETED successfully!"
      ok "  Strategy: ${DEPLOY_STRATEGY}"
      ok "  Task Def: ${NEW_TD_ARN}"
      ok "  Duration: ${SECONDS}s"
      ok "═══════════════════════════════════════════════════════════════"
      exit 0
      ;;
    FAILED)
      err "═══════════════════════════════════════════════════════════════"
      err "  Deployment FAILED — ECS rolled back automatically"
      err "  Strategy: ${DEPLOY_STRATEGY}"
      err "  Check CloudWatch Logs and ECS Events for details"
      err "═══════════════════════════════════════════════════════════════"

      # Print recent events for debugging
      log "📋 Recent service events:"
      aws ecs describe-services \
        ${REGION_FLAG} \
        --cluster "${ECS_CLUSTER}" \
        --services "${ECS_SERVICE}" \
        --query 'services[0].events[:5].[createdAt,message]' \
        --output table 2>/dev/null || true

      exit 1
      ;;
  esac

  sleep 15
done

err "Deployment timed out after ${WAIT_TIMEOUT}s"
err "The deployment may still be in progress. Check the ECS console."
exit 2
