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

SERVICE="DYNAMODB"

create_report_dir

REPORT_FILE="reports/dynamodb-report.csv"
HTML_FILE="reports/dynamodb-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# DYNAMODB TABLES
###############################################################################

TABLES=$(aws dynamodb list-tables \
    --query 'TableNames[*]' \
    --output text 2>/dev/null)

for TABLE in $TABLES
do

    REGION="$DEFAULT_REGION"

###############################################################################
# SERVER SIDE ENCRYPTION
###############################################################################

    SSE=$(aws dynamodb describe-table \
        --table-name "$TABLE" \
        --query 'Table.SSEDescription.Status' \
        --output text 2>/dev/null)

    if [[ "$SSE" == "ENABLED" ]]
    then
        write_result "$REGION" DYNAMODB TABLE_ENCRYPTION "$TABLE" PASS CRITICAL \
        "Server-side encryption enabled"
    else
        write_result "$REGION" DYNAMODB TABLE_ENCRYPTION "$TABLE" FAIL CRITICAL \
        "Server-side encryption disabled"
    fi

###############################################################################
# POINT-IN-TIME RECOVERY
###############################################################################

    PITR=$(aws dynamodb describe-continuous-backups \
        --table-name "$TABLE" \
        --query 'ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus' \
        --output text 2>/dev/null)

    if [[ "$PITR" == "ENABLED" ]]
    then
        write_result "$REGION" DYNAMODB PITR_ENABLED "$TABLE" PASS HIGH \
        "Point-in-time recovery enabled"
    else
        write_result "$REGION" DYNAMODB PITR_ENABLED "$TABLE" FAIL HIGH \
        "Point-in-time recovery disabled"
    fi

###############################################################################
# DELETION PROTECTION
###############################################################################

    DELETE_PROTECTION=$(aws dynamodb describe-table \
        --table-name "$TABLE" \
        --query 'Table.DeletionProtectionEnabled' \
        --output text 2>/dev/null)

    if [[ "$DELETE_PROTECTION" == "True" ]]
    then
        write_result "$REGION" DYNAMODB DELETION_PROTECTION "$TABLE" PASS HIGH \
        "Deletion protection enabled"
    else
        write_result "$REGION" DYNAMODB DELETION_PROTECTION "$TABLE" FAIL HIGH \
        "Deletion protection disabled"
    fi

###############################################################################
# SSE TYPE
###############################################################################

    SSE_TYPE=$(aws dynamodb describe-table \
        --table-name "$TABLE" \
        --query 'Table.SSEDescription.SSEType' \
        --output text 2>/dev/null)

    if [[ -n "$SSE_TYPE" && "$SSE_TYPE" != "None" ]]
    then
        write_result "$REGION" DYNAMODB SSE_TYPE "$TABLE" PASS MEDIUM \
        "$SSE_TYPE"
    else
        write_result "$REGION" DYNAMODB SSE_TYPE "$TABLE" FAIL MEDIUM \
        "SSE type unavailable"
    fi

###############################################################################
# BACKUP STATUS
###############################################################################

    BACKUPS=$(aws dynamodb list-backups \
        --table-name "$TABLE" \
        --query 'BackupSummaries | length(@)' \
        --output text 2>/dev/null)

    if [[ "$BACKUPS" -gt 0 ]]
    then
        write_result "$REGION" DYNAMODB BACKUP_STATUS "$TABLE" PASS MEDIUM \
        "$BACKUPS backup(s) available"
    else
        write_result "$REGION" DYNAMODB BACKUP_STATUS "$TABLE" FAIL MEDIUM \
        "No on-demand backups found"
    fi

###############################################################################
# STREAM ENABLED
###############################################################################

    STREAM=$(aws dynamodb describe-table \
        --table-name "$TABLE" \
        --query 'Table.StreamSpecification.StreamEnabled' \
        --output text 2>/dev/null)

    if [[ "$STREAM" == "True" ]]
    then
        write_result "$REGION" DYNAMODB STREAM_ENABLED "$TABLE" PASS LOW \
        "DynamoDB Stream enabled"
    else
        write_result "$REGION" DYNAMODB STREAM_ENABLED "$TABLE" FAIL LOW \
        "DynamoDB Stream disabled"
    fi

###############################################################################
# TABLE STATUS
###############################################################################

    STATUS=$(aws dynamodb describe-table \
        --table-name "$TABLE" \
        --query 'Table.TableStatus' \
        --output text 2>/dev/null)

    if [[ "$STATUS" == "ACTIVE" ]]
    then
        write_result "$REGION" DYNAMODB TABLE_STATUS "$TABLE" PASS LOW \
        "Table active"
    else
        write_result "$REGION" DYNAMODB TABLE_STATUS "$TABLE" FAIL LOW \
        "Table status: $STATUS"
    fi

###############################################################################
# TABLE TAGS
###############################################################################

    TABLE_ARN=$(aws dynamodb describe-table \
        --table-name "$TABLE" \
        --query 'Table.TableArn' \
        --output text 2>/dev/null)

    TAGS=$(aws dynamodb list-tags-of-resource \
        --resource-arn "$TABLE_ARN" \
        --query 'Tags[*].Key' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" DYNAMODB TABLE_TAGS "$TABLE" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" DYNAMODB TABLE_TAGS "$TABLE" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# TTL CONFIGURATION
###############################################################################

    TTL=$(aws dynamodb describe-time-to-live \
        --table-name "$TABLE" \
        --query 'TimeToLiveDescription.TimeToLiveStatus' \
        --output text 2>/dev/null)

    if [[ "$TTL" == "ENABLED" ]]
    then
        write_result "$REGION" DYNAMODB TTL_CONFIGURATION "$TABLE" PASS LOW \
        "TTL enabled"
    else
        write_result "$REGION" DYNAMODB TTL_CONFIGURATION "$TABLE" FAIL LOW \
        "TTL disabled"
    fi

###############################################################################
# KMS KEY
###############################################################################

    KMS_KEY=$(aws dynamodb describe-table \
        --table-name "$TABLE" \
        --query 'Table.SSEDescription.KMSMasterKeyArn' \
        --output text 2>/dev/null)

    if [[ -n "$KMS_KEY" && "$KMS_KEY" != "None" ]]
    then
        write_result "$REGION" DYNAMODB KMS_KEY "$TABLE" PASS LOW \
        "Customer managed KMS key configured"
    else
        write_result "$REGION" DYNAMODB KMS_KEY "$TABLE" FAIL LOW \
        "AWS managed key or no KMS key configured"
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
    DYNAMODB \
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
echo "DynamoDB Audit Complete"
