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

SERVICE="SECRETSMANAGER"

create_report_dir

REPORT_FILE="reports/secretsmanager-report.csv"
HTML_FILE="reports/secretsmanager-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# SECRETS
###############################################################################

SECRETS=$(aws secretsmanager list-secrets \
    --query 'SecretList[*].ARN' \
    --output text 2>/dev/null)

for SECRET in $SECRETS
do

    REGION="$DEFAULT_REGION"

###############################################################################
# SECRET ROTATION
###############################################################################

    ROTATION=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET" \
        --query 'RotationEnabled' \
        --output text 2>/dev/null)

    if [[ "$ROTATION" == "True" ]]
    then
        write_result "$REGION" SECRETSMANAGER SECRET_ROTATION "$SECRET" PASS HIGH \
        "Rotation enabled"
    else
        write_result "$REGION" SECRETSMANAGER SECRET_ROTATION "$SECRET" FAIL HIGH \
        "Rotation disabled"
    fi

###############################################################################
# KMS ENCRYPTION
###############################################################################

    KMS_KEY=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET" \
        --query 'KmsKeyId' \
        --output text 2>/dev/null)

    if [[ -n "$KMS_KEY" && "$KMS_KEY" != "None" ]]
    then
        write_result "$REGION" SECRETSMANAGER KMS_ENCRYPTION "$SECRET" PASS HIGH \
        "Customer KMS key configured"
    else
        write_result "$REGION" SECRETSMANAGER KMS_ENCRYPTION "$SECRET" FAIL HIGH \
        "Using default encryption"
    fi

###############################################################################
# LAST ROTATED
###############################################################################

    LAST_ROTATED=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET" \
        --query 'LastRotatedDate' \
        --output text 2>/dev/null)

    if [[ -n "$LAST_ROTATED" && "$LAST_ROTATED" != "None" ]]
    then
        write_result "$REGION" SECRETSMANAGER LAST_ROTATED "$SECRET" PASS MEDIUM \
        "Secret rotated previously"
    else
        write_result "$REGION" SECRETSMANAGER LAST_ROTATED "$SECRET" FAIL MEDIUM \
        "Never rotated"
    fi

###############################################################################
# RESOURCE POLICY
###############################################################################

    POLICY=$(aws secretsmanager get-resource-policy \
        --secret-id "$SECRET" \
        --query 'ResourcePolicy' \
        --output text 2>/dev/null)

    if [[ -n "$POLICY" && "$POLICY" != "None" ]]
    then
        write_result "$REGION" SECRETSMANAGER RESOURCE_POLICY "$SECRET" PASS MEDIUM \
        "Resource policy configured"
    else
        write_result "$REGION" SECRETSMANAGER RESOURCE_POLICY "$SECRET" FAIL MEDIUM \
        "No resource policy"
    fi

###############################################################################
# PENDING DELETION
###############################################################################

    DELETED=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET" \
        --query 'DeletedDate' \
        --output text 2>/dev/null)

    if [[ -n "$DELETED" && "$DELETED" != "None" ]]
    then
        write_result "$REGION" SECRETSMANAGER DELETED_SECRET "$SECRET" FAIL HIGH \
        "Secret pending deletion"
    else
        write_result "$REGION" SECRETSMANAGER DELETED_SECRET "$SECRET" PASS HIGH \
        "Secret active"
    fi

###############################################################################
# TAGS
###############################################################################

    TAGS=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET" \
        --query 'Tags[*].Key' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" SECRETSMANAGER TAGS_PRESENT "$SECRET" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" SECRETSMANAGER TAGS_PRESENT "$SECRET" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# DESCRIPTION
###############################################################################

    DESCRIPTION=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET" \
        --query 'Description' \
        --output text 2>/dev/null)

    if [[ -n "$DESCRIPTION" && "$DESCRIPTION" != "None" ]]
    then
        write_result "$REGION" SECRETSMANAGER DESCRIPTION "$SECRET" PASS LOW \
        "Description present"
    else
        write_result "$REGION" SECRETSMANAGER DESCRIPTION "$SECRET" FAIL LOW \
        "Description missing"
    fi

###############################################################################
# REPLICATION
###############################################################################

    REPLICATION=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET" \
        --query 'ReplicationStatus[*].Region' \
        --output text 2>/dev/null)

    if [[ -n "$REPLICATION" && "$REPLICATION" != "None" ]]
    then
        write_result "$REGION" SECRETSMANAGER REPLICATION "$SECRET" PASS LOW \
        "Multi-region replication enabled"
    else
        write_result "$REGION" SECRETSMANAGER REPLICATION "$SECRET" FAIL LOW \
        "No replication configured"
    fi

###############################################################################
# LAST ACCESSED
###############################################################################

    LAST_ACCESSED=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET" \
        --query 'LastAccessedDate' \
        --output text 2>/dev/null)

    if [[ -n "$LAST_ACCESSED" && "$LAST_ACCESSED" != "None" ]]
    then
        write_result "$REGION" SECRETSMANAGER LAST_ACCESSED "$SECRET" PASS LOW \
        "Secret accessed previously"
    else
        write_result "$REGION" SECRETSMANAGER LAST_ACCESSED "$SECRET" FAIL LOW \
        "No access information available"
    fi

###############################################################################
# ROTATION LAMBDA
###############################################################################

    ROTATION_LAMBDA=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET" \
        --query 'RotationLambdaARN' \
        --output text 2>/dev/null)

    if [[ -n "$ROTATION_LAMBDA" && "$ROTATION_LAMBDA" != "None" ]]
    then
        write_result "$REGION" SECRETSMANAGER ROTATION_LAMBDA "$SECRET" PASS LOW \
        "Rotation Lambda configured"
    else
        write_result "$REGION" SECRETSMANAGER ROTATION_LAMBDA "$SECRET" FAIL LOW \
        "Rotation Lambda not configured"
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
    SECRETSMANAGER \
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
echo "Secrets Manager Audit Complete"
