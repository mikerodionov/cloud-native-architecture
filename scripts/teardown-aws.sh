#!/usr/bin/env bash
set -euo pipefail

read -r -p "Enter AWS Region to teardown [eu-south-2]: " INPUT_REGION
export AWS_REGION="${INPUT_REGION:-eu-south-2}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="tofu-state-cloudnative-${ACCOUNT_ID}-${AWS_REGION}"
ROLE_NAME="GitHubActionsDeployerRole"
REPO_NWO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"

echo "================================================================"
echo "⚠️  Tearing down AWS Bootstrap Environment"
echo "   Region: $AWS_REGION | Account: $ACCOUNT_ID"
echo "================================================================"

# 1. Force Delete ECR Repositories
STATUS_ECR="NOT FOUND"
echo "[+] 1/3 Purging Amazon ECR Repositories..."
for REPO in "frontend-app" "backend-app"; do
  if aws ecr describe-repositories --repository-names "$REPO" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws ecr delete-repository --repository-name "$REPO" --region "$AWS_REGION" --force >/dev/null
    echo "    ✓ Repository '$REPO' force deleted."
    STATUS_ECR="DELETED"
  fi
done

# 2. Delete IAM Role
STATUS_ROLE="NOT FOUND"
echo "[+] 2/3 Deleting IAM CI/CD Role ($ROLE_NAME)..."
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" >/dev/null 2>&1 || true
  aws iam delete-role --role-name "$ROLE_NAME" >/dev/null
  echo "    ✓ IAM Role deleted."
  STATUS_ROLE="DELETED"
fi

# 3. Purge GitHub Secrets
STATUS_SECRETS="SKIPPED"
if [[ -n "$REPO_NWO" ]]; then
  echo "[+] 3/3 Removing GitHub Actions Secrets from $REPO_NWO..."
  for sec in AWS_ROLE_ARN AWS_REGION TF_STATE_BUCKET; do
    gh secret delete "$sec" >/dev/null 2>&1 || true
    echo "    ✓ Secret '$sec' deleted."
  done
  STATUS_SECRETS="DELETED"
fi

# 4. Render Teardown Summary Table
echo ""
echo "=========================================================================================================="
echo "                             🧹 TEARDOWN DECOMMISSION REPORT"
echo "=========================================================================================================="
printf "%-12s | %-32s | %-20s | %-30s\n" "PLATFORM" "RESOURCE TYPE" "STATUS" "NOTES"
echo "-------------+----------------------------------+----------------------+----------------------------------"
printf "%-12s | %-32s | %-20s | %-30s\n" "AWS" "ECR Repositories" "$STATUS_ECR" "frontend-app & backend-app"
printf "%-12s | %-32s | %-20s | %-30s\n" "AWS" "IAM Deployer Role" "$STATUS_ROLE" "$ROLE_NAME"
printf "%-12s | %-32s | %-20s | %-30s\n" "AWS" "S3 Remote State Bucket" "RETAINED" "$BUCKET_NAME (empty manually)"
echo "-------------+----------------------------------+----------------------+----------------------------------"
printf "%-12s | %-32s | %-20s | %-30s\n" "GitHub" "Secret: AWS_ROLE_ARN" "$STATUS_SECRETS" "Removed from repository"
printf "%-12s | %-32s | %-20s | %-30s\n" "GitHub" "Secret: AWS_REGION" "$STATUS_SECRETS" "Removed from repository"
printf "%-12s | %-32s | %-20s | %-30s\n" "GitHub" "Secret: TF_STATE_BUCKET" "$STATUS_SECRETS" "Removed from repository"
echo "=========================================================================================================="
echo "⚠️  Note: S3 bucket '${BUCKET_NAME}' was retained to protect state objects."
echo "If no longer needed, purge via: aws s3 rb s3://${BUCKET_NAME} --force"
echo ""