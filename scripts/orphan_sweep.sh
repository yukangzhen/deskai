#!/usr/bin/env bash
#
# deskai — orphan sweep
#
# Run before you stop working. Every session. Reports only; deletes nothing.
# For an emergency stop that actually deletes, use panic_teardown.sh
#
set -uo pipefail

REGION="${AWS_REGION:-ap-southeast-1}"
TODAY=$(date -u +%Y-%m-%d)
FOUND=0

echo "======================================================"
echo " deskai orphan sweep · ${TODAY} · ${REGION}"
echo "======================================================"

echo
echo "--- Ephemeral resources past TeardownBy"
if tagged_resources=$(aws resourcegroupstaggingapi get-resources --region "$REGION" \
  --tag-filters Key=Project,Values=deskai Key=Ephemeral,Values=true \
  --query 'ResourceTagMappingList[].[ResourceARN, Tags[?Key==`TeardownBy`].Value|[0], Tags[?Key==`Sprint`].Value|[0]]' \
  --output text 2>&1); then
  while read -r arn teardown sprint; do
    [ -z "${arn:-}" ] && continue
    if [[ "$teardown" != "never" && "$teardown" < "$TODAY" ]]; then
      echo "  OVERDUE [$sprint] $arn (due $teardown)"
      FOUND=1
    else
      echo "  ok      [$sprint] $arn (due $teardown)"
    fi
  done <<< "$tagged_resources"
else
  echo "  CHECK FAILED: ${tagged_resources}"
  FOUND=1
fi

echo
echo "--- Big-ticket services (tag-independent)"
check() {
  local label="$1"; shift
  local out
  if ! out=$(aws "$@" --region "$REGION" --output text 2>&1); then
    echo "  CHECK FAILED  ${label}: ${out}"
    FOUND=1
    return
  fi
  if [ -n "$out" ] && [ "$out" != "None" ]; then
    echo "  ALIVE  ${label}: ${out}"
    FOUND=1
  else
    echo "  clean  ${label}"
  fi
}

check_kendra() {
  local out
  if ! out=$(aws kendra list-indices --region "$REGION" \
      --query 'IndexConfigurationSummaryItems[].Name' --output text 2>&1); then
    if [[ "$out" == *"SubscriptionRequiredException"* ]]; then
      echo "  clean  Kendra indexes (service not subscribed)"
      return
    fi
    echo "  CHECK FAILED  Kendra indexes: ${out}"
    FOUND=1
    return
  fi
  if [ -n "$out" ] && [ "$out" != "None" ]; then
    echo "  ALIVE  Kendra indexes: ${out}"
    FOUND=1
  else
    echo "  clean  Kendra indexes"
  fi
}

check "OpenSearch Serverless" opensearchserverless list-collections --query 'collectionSummaries[].name'
check "OpenSearch domains"    opensearch list-domain-names        --query 'DomainNames[].DomainName'
check "SageMaker endpoints"   sagemaker list-endpoints            --query 'Endpoints[].EndpointName'
check "SageMaker training"    sagemaker list-training-jobs --status-equals InProgress --query 'TrainingJobSummaries[].TrainingJobName'
check "Aurora/RDS clusters"   rds describe-db-clusters            --query 'DBClusters[].DBClusterIdentifier'
check "RDS instances"         rds describe-db-instances           --query 'DBInstances[].DBInstanceIdentifier'
check "Bedrock KBs"           bedrock-agent list-knowledge-bases  --query 'knowledgeBaseSummaries[].name'
check "Bedrock agents"        bedrock-agent list-agents           --query 'agentSummaries[].agentName'
check_kendra
check "NAT gateways"          ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'

echo
echo "--- TRIPWIRE: provisioned throughput (must always be empty)"
if ! pt=$(aws bedrock list-provisioned-model-throughputs --region "$REGION" \
     --query 'provisionedModelSummaries[].provisionedModelName' --output text 2>&1); then
  echo "  CHECK FAILED: ${pt}"
  FOUND=1
elif [ -n "$pt" ] && [ "$pt" != "None" ]; then
  echo "  *** CRITICAL: PROVISIONED THROUGHPUT EXISTS: $pt ***"
  echo "  *** Delete immediately — this bills hourly and may be uncancellable. ***"
  FOUND=1
else
  echo "  clean  no provisioned throughput"
fi

echo
echo "======================================================"
if [ "$FOUND" -eq 0 ]; then
  echo " SWEEP CLEAN — safe to stop."
else
  echo " SWEEP FOUND LIVE RESOURCES — review above before stopping."
  echo " If intentional, confirm they are in STATE.md under 'Live at rest'."
fi
echo "======================================================"
