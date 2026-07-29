#!/usr/bin/env bash
#
# deskai — EMERGENCY STOP
#
# Deletes every HOURLY-BILLED resource belonging to this project, across all
# regions used by the programme. Run this when you must stop work immediately
# and cannot complete a sprint's normal teardown.
#
# Does NOT touch: S3 buckets, code, evidence, benchmarks, IAM, Prompt
# Management, CloudWatch dashboards, or anything that bills negligibly at rest.
#
# Usage:  ./panic_teardown.sh          # list only, deletes nothing
#         ./panic_teardown.sh --delete # prompts, then deletes
#
set -uo pipefail

REGIONS=("ap-southeast-1" "ap-southeast-2" "us-east-1")
DELETE=false
[[ "${1:-}" == "--delete" ]] && DELETE=true

FOUND=0
declare -a ACTIONS

note() { echo "  FOUND  $1"; ACTIONS+=("$2"); FOUND=1; }

echo "======================================================="
echo " deskai EMERGENCY STOP — hourly-billed resources"
echo " mode: $([ "$DELETE" = true ] && echo 'DELETE' || echo 'LIST ONLY')"
echo "======================================================="

for R in "${REGIONS[@]}"; do
  echo
  echo "--- region: $R"

  # --- Bedrock Provisioned Throughput — must never exist ---------------------
  pt=$(aws bedrock list-provisioned-model-throughputs --region "$R" \
        --query 'provisionedModelSummaries[].provisionedModelArn' --output text 2>/dev/null)
  if [ -n "$pt" ] && [ "$pt" != "None" ]; then
    echo "  *** CRITICAL: PROVISIONED THROUGHPUT PRESENT ***"
    for arn in $pt; do
      note "provisioned-throughput $arn" \
           "aws bedrock delete-provisioned-model-throughput --provisioned-model-id $arn --region $R"
    done
  fi

  # --- OpenSearch Serverless (~\$0.96/hr at 4 OCU) ---------------------------
  for id in $(aws opensearchserverless list-collections --region "$R" \
              --query 'collectionSummaries[].id' --output text 2>/dev/null); do
    [ "$id" = "None" ] && continue
    note "opensearch-serverless collection $id" \
         "aws opensearchserverless delete-collection --id $id --region $R"
  done

  # --- OpenSearch managed domains -------------------------------------------
  for d in $(aws opensearch list-domain-names --region "$R" \
             --query 'DomainNames[?starts_with(DomainName,`deskai`)].DomainName' --output text 2>/dev/null); do
    [ "$d" = "None" ] && continue
    note "opensearch domain $d" \
         "aws opensearch delete-domain --domain-name $d --region $R"
  done

  # --- SageMaker endpoints (billed per instance-hour) -----------------------
  for e in $(aws sagemaker list-endpoints --region "$R" \
             --query 'Endpoints[].EndpointName' --output text 2>/dev/null); do
    [ "$e" = "None" ] && continue
    note "sagemaker endpoint $e" \
         "aws sagemaker delete-endpoint --endpoint-name $e --region $R"
  done

  # --- SageMaker training jobs still running --------------------------------
  for j in $(aws sagemaker list-training-jobs --status-equals InProgress --region "$R" \
             --query 'TrainingJobSummaries[].TrainingJobName' --output text 2>/dev/null); do
    [ "$j" = "None" ] && continue
    note "sagemaker training job (running) $j" \
         "aws sagemaker stop-training-job --training-job-name $j --region $R"
  done

  # --- Aurora / RDS clusters -------------------------------------------------
  for c in $(aws rds describe-db-clusters --region "$R" \
             --query 'DBClusters[?starts_with(DBClusterIdentifier,`deskai`)].DBClusterIdentifier' \
             --output text 2>/dev/null); do
    [ "$c" = "None" ] && continue
    note "aurora cluster $c" \
         "aws rds delete-db-cluster --db-cluster-identifier $c --skip-final-snapshot --region $R"
  done
  for i in $(aws rds describe-db-instances --region "$R" \
             --query 'DBInstances[?starts_with(DBInstanceIdentifier,`deskai`)].DBInstanceIdentifier' \
             --output text 2>/dev/null); do
    [ "$i" = "None" ] && continue
    note "rds instance $i" \
         "aws rds delete-db-instance --db-instance-identifier $i --skip-final-snapshot --region $R"
  done

  # --- Kendra indexes (high hourly floor) -----------------------------------
  for k in $(aws kendra list-indices --region "$R" \
             --query 'IndexConfigurationSummaryItems[].Id' --output text 2>/dev/null); do
    [ "$k" = "None" ] && continue
    note "kendra index $k" "aws kendra delete-index --id $k --region $R"
  done

  # --- NAT Gateways (~\$0.05/hr + data) -------------------------------------
  for n in $(aws ec2 describe-nat-gateways --region "$R" \
             --filter Name=state,Values=available \
             --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null); do
    [ "$n" = "None" ] && continue
    note "nat gateway $n" "aws ec2 delete-nat-gateway --nat-gateway-id $n --region $R"
  done

  # --- AWS Config recorder (accrues quietly) --------------------------------
  rec=$(aws configservice describe-configuration-recorder-status --region "$R" \
        --query 'ConfigurationRecordersStatus[?recording==`true`].name' --output text 2>/dev/null)
  if [ -n "$rec" ] && [ "$rec" != "None" ]; then
    note "config recorder (recording) $rec" \
         "aws configservice stop-configuration-recorder --configuration-recorder-name $rec --region $R"
  fi

  # --- Macie ----------------------------------------------------------------
  if aws macie2 get-macie-session --region "$R" >/dev/null 2>&1; then
    note "macie enabled" "aws macie2 disable-macie --region $R"
  fi
done

echo
echo "======================================================="
if [ "$FOUND" -eq 0 ]; then
  echo " CLEAN — no hourly-billed resources running."
  echo " Safe to pause."
  exit 0
fi

echo " ${#ACTIONS[@]} billable resource(s) found."
echo "======================================================="
printf '%s\n' "${ACTIONS[@]}"
echo

if [ "$DELETE" != true ]; then
  echo "LIST ONLY. Re-run with --delete to execute the commands above."
  exit 1
fi

echo "These deletions are IRREVERSIBLE. Data in Aurora/OpenSearch will be lost."
read -r -p "Type DELETE to proceed: " confirm
if [ "$confirm" != "DELETE" ]; then
  echo "Aborted. Nothing deleted."
  exit 1
fi

for cmd in "${ACTIONS[@]}"; do
  echo ">> $cmd"
  eval "$cmd" || echo "   (failed — may need manual removal, or a dependency deleted first)"
done

echo
echo "Deletion commands issued. Some resources delete asynchronously."
echo "Re-run this script in 5 minutes to confirm, then run orphan_sweep.sh."
