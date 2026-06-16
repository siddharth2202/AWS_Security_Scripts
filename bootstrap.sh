#!/bin/bash

set -euo pipefail

echo
echo "======================================="
echo " AWS Security Audit Framework Setup"
echo "======================================="
echo

###############################################################################
# VERIFY AWS ACCESS
###############################################################################

ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account \
    --output text 2>/dev/null)

if [[ -z "$ACCOUNT_ID" ]]
then
    echo "ERROR: Unable to determine AWS Account ID"
    echo "Check AWS credentials / CloudShell session"
    exit 1
fi

echo "Account ID : $ACCOUNT_ID"

###############################################################################
# REGION
###############################################################################

REGION=$(aws configure get region)

if [[ -z "$REGION" ]]
then

    REGION="ap-south-1"

    aws configure set region "$REGION"

    echo "Default region not configured"
    echo "Using: $REGION"

fi

echo "Region     : $REGION"

###############################################################################
# REPORT BUCKET
###############################################################################

REPORT_BUCKET="aws-security-audit-${ACCOUNT_ID}"

echo
echo "Report Bucket : $REPORT_BUCKET"

###############################################################################
# CREATE BUCKET IF NEEDED
###############################################################################

if aws s3api head-bucket \
    --bucket "$REPORT_BUCKET" \
    >/dev/null 2>&1
then

    echo "Bucket already exists"

else

    echo "Creating bucket..."

    if [[ "$REGION" == "us-east-1" ]]
    then

        aws s3api create-bucket \
            --bucket "$REPORT_BUCKET"

    else

        aws s3api create-bucket \
            --bucket "$REPORT_BUCKET" \
            --region "$REGION" \
            --create-bucket-configuration \
            LocationConstraint="$REGION"

    fi

    echo "Bucket created"

fi

###############################################################################
# CREATE DIRECTORIES
###############################################################################

mkdir -p reports
mkdir -p logs

touch reports/.gitkeep
touch logs/.gitkeep

###############################################################################
# CONFIG.CONF
###############################################################################

cat > config.conf <<EOF
REPORT_BUCKET=${REPORT_BUCKET}
AUTO_UPLOAD=true
DEFAULT_REGION=${REGION}
EOF

echo
echo "config.conf created"

###############################################################################
# COMPLETE
###############################################################################

echo
echo "======================================="
echo " Setup Complete"
echo "======================================="
echo
echo "Bucket      : $REPORT_BUCKET"
echo "Region      : $REGION"
echo "Config File : config.conf"
echo
echo "You can now run:"
echo
echo "./check-iam.sh"
echo
