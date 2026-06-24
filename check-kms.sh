#!/bin/bash
set -uo pipefail

if [[ ! -f "./bootstrap.sh" ]]
then
    echo
    echo "ERROR: bootstrap.sh not found"
    echo
    exit 1
fi

if [[ ! -f "./config.conf" ]]
then
    echo
    echo "Bootstrap not initialized. Running ./bootstrap.sh"
    echo

    chmod +x bootstrap.sh
    ./bootstrap.sh

    if [[ ! -f "./config.conf" ]]
    then
        echo
        echo "ERROR: bootstrap failed"
        echo
        exit 1
    fi
fi

source ./common.sh
source ./config.conf

SERVICE="KMS"

create_report_dir

REPORT_FILE="reports/kms-report.csv"
HTML_FILE="reports/kms-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# KMS KEYS
###############################################################################

KEYS=$(aws kms list-keys \
    --query 'Keys[*].KeyId' \
    --output text 2>/dev/null)

for KEY in $KEYS
do

    REGION="$DEFAULT_REGION"

###############################################################################
# KEY ENABLED
###############################################################################

    ENABLED=$(aws kms describe-key \
        --key-id "$KEY" \
        --query 'KeyMetadata.Enabled' \
        --output text 2>/dev/null)

    if [[ "$ENABLED" == "True" ]]
    then
        write_result "$REGION" KMS KEY_ENABLED "$KEY" PASS HIGH \
        "Key enabled"
    else
        write_result "$REGION" KMS KEY_ENABLED "$KEY" FAIL HIGH \
        "Key disabled"
    fi

###############################################################################
# KEY ROTATION
###############################################################################

    ROTATION=$(aws kms get-key-rotation-status \
        --key-id "$KEY" \
        --query 'KeyRotationEnabled' \
        --output text 2>/dev/null)

    if [[ "$ROTATION" == "True" ]]
    then
        write_result "$REGION" KMS KEY_ROTATION "$KEY" PASS HIGH \
        "Key rotation enabled"
    else
        write_result "$REGION" KMS KEY_ROTATION "$KEY" FAIL HIGH \
        "Key rotation disabled"
    fi

###############################################################################
# CUSTOMER MANAGED KEY
###############################################################################

    MANAGER=$(aws kms describe-key \
        --key-id "$KEY" \
        --query 'KeyMetadata.KeyManager' \
        --output text 2>/dev/null)

    if [[ "$MANAGER" == "CUSTOMER" ]]
    then
        write_result "$REGION" KMS CUSTOMER_MANAGED_KEY "$KEY" PASS LOW \
        "Customer managed key"
    else
        write_result "$REGION" KMS CUSTOMER_MANAGED_KEY "$KEY" PASS LOW \
        "AWS managed key"
    fi

###############################################################################
# KEY USAGE
###############################################################################

    USAGE=$(aws kms describe-key \
        --key-id "$KEY" \
        --query 'KeyMetadata.KeyUsage' \
        --output text 2>/dev/null)

    if [[ "$USAGE" == "ENCRYPT_DECRYPT" ]]
    then
        write_result "$REGION" KMS KEY_USAGE "$KEY" PASS LOW \
        "Encryption key"
    else
        write_result "$REGION" KMS KEY_USAGE "$KEY" PASS LOW \
        "$USAGE"
    fi

###############################################################################
# KEY STATE
###############################################################################

    STATE=$(aws kms describe-key \
        --key-id "$KEY" \
        --query 'KeyMetadata.KeyState' \
        --output text 2>/dev/null)

    if [[ "$STATE" == "Enabled" ]]
    then
        write_result "$REGION" KMS KEY_STATE "$KEY" PASS HIGH \
        "Key state healthy"
    else
        write_result "$REGION" KMS KEY_STATE "$KEY" FAIL HIGH \
        "Key state: $STATE"
    fi

###############################################################################
# KEY POLICY
###############################################################################

    POLICY=$(aws kms get-key-policy \
        --key-id "$KEY" \
        --policy-name default \
        --query 'Policy' \
        --output text 2>/dev/null)

    if [[ -n "$POLICY" && "$POLICY" != "None" ]]
    then
        write_result "$REGION" KMS KEY_POLICY "$KEY" PASS MEDIUM \
        "Default key policy present"
    else
        write_result "$REGION" KMS KEY_POLICY "$KEY" FAIL MEDIUM \
        "Key policy missing"
    fi

###############################################################################
# MULTI REGION KEY
###############################################################################

    MULTI_REGION=$(aws kms describe-key \
        --key-id "$KEY" \
        --query 'KeyMetadata.MultiRegion' \
        --output text 2>/dev/null)

    if [[ "$MULTI_REGION" == "True" ]]
    then
        write_result "$REGION" KMS MULTI_REGION_KEY "$KEY" PASS LOW \
        "Multi-region key enabled"
    else
        write_result "$REGION" KMS MULTI_REGION_KEY "$KEY" PASS LOW \
        "Single-region key"
    fi

###############################################################################
# KEY DELETION
###############################################################################

    STATE=$(aws kms describe-key \
        --key-id "$KEY" \
        --query 'KeyMetadata.KeyState' \
        --output text 2>/dev/null)

    if [[ "$STATE" == "PendingDeletion" ]]
    then
        write_result "$REGION" KMS KEY_DELETION "$KEY" FAIL HIGH \
        "Key scheduled for deletion"
    else
        write_result "$REGION" KMS KEY_DELETION "$KEY" PASS HIGH \
        "Key not pending deletion"
    fi

###############################################################################
# KEY TAGS
###############################################################################

    TAGS=$(aws kms list-resource-tags \
        --key-id "$KEY" \
        --query 'Tags[*].TagKey' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" KMS KEY_TAGS "$KEY" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" KMS KEY_TAGS "$KEY" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# KEY DESCRIPTION
###############################################################################

    DESCRIPTION=$(aws kms describe-key \
        --key-id "$KEY" \
        --query 'KeyMetadata.Description' \
        --output text 2>/dev/null)

    if [[ -n "$DESCRIPTION" && "$DESCRIPTION" != "None" ]]
    then
        write_result "$REGION" KMS KEY_DESCRIPTION "$KEY" PASS LOW \
        "Description present"
    else
        write_result "$REGION" KMS KEY_DESCRIPTION "$KEY" FAIL LOW \
        "Description missing"
    fi

done

###############################################################################
# HTML REPORT
###############################################################################

generate_html "$REPORT_FILE" "$HTML_FILE"

###############################################################################
# S3 UPLOAD
###############################################################################

if validate_bucket
then

    upload_reports \
    KMS \
    "$REPORT_FILE" \
    "$HTML_FILE"

else

    echo
    echo "ERROR: Report upload skipped"
    echo
    exit 1

fi

###############################################################################
# COMPLETE
###############################################################################

echo
echo "CSV Report : $REPORT_FILE"
echo "HTML Report: $HTML_FILE"
echo
echo "KMS Audit Complete"
