#!/bin/bash
# Migrate EBS volumes from gp2 to gp3
# gp3 is 20% cheaper and has better baseline performance
#
# Usage:
#   ./migrate-gp2-to-gp3.sh              # current region only
#   ./migrate-gp2-to-gp3.sh --all-regions # all AWS regions

set -e

# Configuration
OLD_TYPE="gp2"
NEW_TYPE="gp3"
BATCH_SIZE=10

migrate_region() {
  local region=$1
  echo ""
  echo "=========================================="
  echo "  Region: $region"
  echo "=========================================="

  VOLUMES=$(aws ec2 describe-volumes \
    --region "$region" \
    --filters "Name=volume-type,Values=$OLD_TYPE" \
    --query "Volumes[*].[VolumeId,Size,State,Attachments[0].InstanceId]" \
    --output text)

  if [ -z "$VOLUMES" ]; then
    echo "No $OLD_TYPE volumes found. Skipping."
    return
  fi

  TOTAL=$(echo "$VOLUMES" | wc -l | tr -d ' ')
  echo ""
  echo "Found $TOTAL $OLD_TYPE volumes to migrate → $NEW_TYPE:"
  echo ""
  printf "%-22s %-10s %-12s %-20s\n" "Volume ID" "Size (GB)" "State" "Attached To"
  echo "--------------------------------------------------------------"
  echo "$VOLUMES" | while read -r vid size state instance; do
    instance=${instance:-"(not attached)"}
    printf "%-22s %-10s %-12s %-20s\n" "$vid" "$size" "$state" "$instance"
  done

  echo ""
  read -p "Migrate $TOTAL volumes in $region? (y/n/a=all remaining): " confirm
  if [[ "$confirm" == "a" || "$confirm" == "A" ]]; then
    AUTO_APPROVE=true
  elif [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Skipped $region."
    return
  fi

  echo ""
  echo "Migrating in batches of $BATCH_SIZE..."
  echo ""

  count=0
  echo "$VOLUMES" | while read -r vid size state instance; do
    count=$((count + 1))

    echo "[$count/$TOTAL] Migrating $vid ($size GB) → $NEW_TYPE..."
    if aws ec2 modify-volume --region "$region" --volume-id "$vid" --volume-type "$NEW_TYPE" --output text > /dev/null 2>&1; then
      echo "  ✓ $vid migration started"
    else
      echo "  ✗ $vid failed"
    fi

    # Batch throttle
    if [ $((count % BATCH_SIZE)) -eq 0 ] && [ "$count" -lt "$TOTAL" ]; then
      echo ""
      echo "Batch complete. Waiting 5 seconds to avoid throttling..."
      sleep 5
      echo ""
    fi
  done

  echo ""
  echo "Done with $region. Migrated $TOTAL volumes."
}

# Main
AUTO_APPROVE=false

if [[ "$1" == "--all-regions" ]]; then
  echo "Fetching all AWS regions..."
  REGIONS=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)
  REGION_COUNT=$(echo "$REGIONS" | wc -w | tr -d ' ')
  echo "Found $REGION_COUNT regions. Scanning each for $OLD_TYPE volumes..."

  for region in $REGIONS; do
    migrate_region "$region"
  done

  echo ""
  echo "=========================================="
  echo "  All regions complete."
  echo "=========================================="
else
  CURRENT_REGION=$(aws configure get region 2>/dev/null || echo "${AWS_REGION:-us-east-1}")
  echo "Running in region: $CURRENT_REGION"
  echo "(Use --all-regions to migrate across all AWS regions)"
  migrate_region "$CURRENT_REGION"
fi

echo ""
echo "Migrations happen in the background. Check status with:"
echo ""
echo "  aws ec2 describe-volumes-modifications --filters Name=modification-state,Values=modifying"
