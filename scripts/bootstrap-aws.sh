#!/usr/bin/env bash
set -euo pipefail

# 1. Prerequisite Checks
for cmd in aws gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ ERROR: '$cmd' is required but not installed/in PATH."
    exit 1
  fi
done

if [[ ! -d .git ]]; then
  echo "❌ ERROR: This directory is not a Git repository. Run 'git init' first."
  exit 1
fi

REPO_NWO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
if [[ -z "$REPO_NWO" ]]; then
  echo "❌ ERROR: Unable to detect GitHub repository via gh CLI. Ensure you pushed to origin."
  exit 1
fi

# 2. Configuration & Prompts
read -r -p "Enter AWS Region [eu-south-2]: " INPUT_REGION
export AWS_REGION="${INPUT_REGION:-eu-south-2}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="tofu-state-cloudnative-${ACCOUNT_ID}-${AWS_REGION}"
ROLE_NAME="GitHubActionsDeployerRole"
OIDC_PROVIDER_URL="token.actions.githubusercontent.com"
OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}"

echo "================================================================"
echo "🚀 Bootstrapping AWS Environment (OIDC Mode)"
echo "   Region: $AWS_REGION | Account: $ACCOUNT_ID"
echo "   Repo:   $REPO_NWO"
echo "================================================================"

# 3. Create S3 State Bucket
echo "[+] 1/5 Ensuring S3 State Bucket exists: $BUCKET_NAME"
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
  aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --versioning-configuration Status=Enabled
  echo "    ✓ Bucket created with versioning enabled."
else
  echo "    ✓ Bucket already exists."
fi

# 4. Create Amazon ECR Repositories
echo "[+] 2/5 Ensuring ECR Repositories exist..."
for REPO in "frontend-app" "backend-app"; do
  if ! aws ecr describe-repositories --repository-names "$REPO" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws ecr create-repository --repository-name "$REPO" --region "$AWS_REGION" >/dev/null
    echo "    ✓ Repository '$REPO' created."
  else
    echo "    ✓ Repository '$REPO' already exists."
  fi
done

# 5. Create IAM OIDC Provider
echo "[+] 3/5 Ensuring GitHub OIDC Provider exists..."
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" >/dev/null 2>&1; then
  aws iam create-open-id-connect-provider \
    --url "https://${OIDC_PROVIDER_URL}" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" "1c58a3a8518e8759bf075b76b750d4f2df264fcd" >/dev/null
  echo "    ✓ OIDC Provider created."
else
  echo "    ✓ OIDC Provider already exists."
fi

# 6. Create IAM Role with OIDC Trust Policy
echo "[+] 4/5 Ensuring CI/CD IAM Role exists: $ROLE_NAME"
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "$OIDC_PROVIDER_ARN" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": { "${OIDC_PROVIDER_URL}:aud": "sts.amazonaws.com" },
        "StringLike": { "${OIDC_PROVIDER_URL}:sub": "repo:${REPO_NWO}:*" }
      }
    }
  ]
}
EOF
)

if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY" >/dev/null
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
  echo "    ✓ IAM Role created and AdministratorAccess attached."
else
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$TRUST_POLICY"
  echo "    ✓ IAM Role already exists. Trust policy updated."
fi

# 7. Inject GitHub Secrets
echo "[+] 5/5 Pushing secrets to GitHub repository ($REPO_NWO)..."
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

gh secret set AWS_ROLE_ARN -b"$ROLE_ARN"
gh secret set AWS_REGION -b"$AWS_REGION"
gh secret set TF_STATE_BUCKET -b"$BUCKET_NAME"

# 8. Render Summary Table
echo ""
echo "=========================================================================================================="
echo "                           🎉 BOOTSTRAP PROVISIONING SUMMARY REPORT"
echo "=========================================================================================================="
printf "%-12s | %-32s | %-52s\n" "PLATFORM" "RESOURCE TYPE" "IDENTIFIER / VALUE"
echo "-------------+----------------------------------+---------------------------------------------------------"
printf "%-12s | %-32s | %-52s\n" "AWS" "S3 Remote State Bucket" "$BUCKET_NAME"
printf "%-12s | %-32s | %-52s\n" "AWS" "ECR Repository (Frontend)" "frontend-app"
printf "%-12s | %-32s | %-52s\n" "AWS" "ECR Repository (Backend)" "backend-app"
printf "%-12s | %-32s | %-52s\n" "AWS" "IAM OIDC Provider" "$OIDC_PROVIDER_URL"
printf "%-12s | %-32s | %-52s\n" "AWS" "IAM Deployer Role" "$ROLE_NAME"
echo "-------------+----------------------------------+---------------------------------------------------------"
printf "%-12s | %-32s | %-52s\n" "GitHub" "Repository Binding" "$REPO_NWO"
printf "%-12s | %-32s | %-52s\n" "GitHub" "Secret: AWS_ROLE_ARN" "$ROLE_ARN"
printf "%-12s | %-32s | %-52s\n" "GitHub" "Secret: AWS_REGION" "$AWS_REGION"
printf "%-12s | %-32s | %-52s\n" "GitHub" "Secret: TF_STATE_BUCKET" "$BUCKET_NAME"
echo "=========================================================================================================="
echo "Status: READY for OpenTofu initialization in opentofu/aws/"
echo ""