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

SERVICE="ELASTICACHE"

create_report_dir

REPORT_FILE="reports/elasticache-report.csv"
HTML_FILE="reports/elasticache-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# CACHE CLUSTERS
###############################################################################

CLUSTERS=$(aws elasticache describe-cache-clusters \
    --show-cache-node-info \
    --query 'CacheClusters[*].CacheClusterId' \
    --output text 2>/dev/null)

for CLUSTER in $CLUSTERS
do

    REGION="$DEFAULT_REGION"

###############################################################################
# AT REST ENCRYPTION
###############################################################################

    REST=$(aws elasticache describe-cache-clusters \
        --cache-cluster-id "$CLUSTER" \
        --show-cache-node-info \
        --query 'CacheClusters[0].AtRestEncryptionEnabled' \
        --output text 2>/dev/null)

    if [[ "$REST" == "True" ]]
    then
        write_result "$REGION" ELASTICACHE AT_REST_ENCRYPTION "$CLUSTER" PASS CRITICAL \
        "Encryption at rest enabled"
    else
        write_result "$REGION" ELASTICACHE AT_REST_ENCRYPTION "$CLUSTER" FAIL CRITICAL \
        "Encryption at rest disabled"
    fi

###############################################################################
# TRANSIT ENCRYPTION
###############################################################################

    TRANSIT=$(aws elasticache describe-cache-clusters \
        --cache-cluster-id "$CLUSTER" \
        --show-cache-node-info \
        --query 'CacheClusters[0].TransitEncryptionEnabled' \
        --output text 2>/dev/null)

    if [[ "$TRANSIT" == "True" ]]
    then
        write_result "$REGION" ELASTICACHE TRANSIT_ENCRYPTION "$CLUSTER" PASS CRITICAL \
        "Encryption in transit enabled"
    else
        write_result "$REGION" ELASTICACHE TRANSIT_ENCRYPTION "$CLUSTER" FAIL CRITICAL \
        "Encryption in transit disabled"
    fi

###############################################################################
# AUTH TOKEN
###############################################################################

    AUTH=$(aws elasticache describe-cache-clusters \
        --cache-cluster-id "$CLUSTER" \
        --show-cache-node-info \
        --query 'CacheClusters[0].AuthTokenEnabled' \
        --output text 2>/dev/null)

    if [[ "$AUTH" == "True" ]]
    then
        write_result "$REGION" ELASTICACHE AUTH_TOKEN_ENABLED "$CLUSTER" PASS HIGH \
        "Auth token enabled"
    else
        write_result "$REGION" ELASTICACHE AUTH_TOKEN_ENABLED "$CLUSTER" FAIL HIGH \
        "Auth token disabled"
    fi

###############################################################################
# PUBLIC ACCESS
###############################################################################

    NETWORK=$(aws elasticache describe-cache-clusters \
        --cache-cluster-id "$CLUSTER" \
        --show-cache-node-info \
        --query 'CacheClusters[0].PreferredAvailabilityZone' \
        --output text 2>/dev/null)

    if [[ -n "$NETWORK" && "$NETWORK" != "None" ]]
    then
        write_result "$REGION" ELASTICACHE PUBLIC_ACCESS "$CLUSTER" PASS HIGH \
        "Cluster deployed inside VPC"
    else
        write_result "$REGION" ELASTICACHE PUBLIC_ACCESS "$CLUSTER" FAIL HIGH \
        "Unable to determine VPC placement"
    fi

###############################################################################
# AUTOMATIC BACKUPS
###############################################################################

    RETENTION=$(aws elasticache describe-cache-clusters \
        --cache-cluster-id "$CLUSTER" \
        --show-cache-node-info \
        --query 'CacheClusters[0].SnapshotRetentionLimit' \
        --output text 2>/dev/null)

    if [[ "$RETENTION" -gt 0 ]]
    then
        write_result "$REGION" ELASTICACHE AUTOMATIC_BACKUPS "$CLUSTER" PASS MEDIUM \
        "$RETENTION day retention"
    else
        write_result "$REGION" ELASTICACHE AUTOMATIC_BACKUPS "$CLUSTER" FAIL MEDIUM \
        "Automatic backups disabled"
    fi

    ###############################################################################
# AUTO MINOR VERSION UPGRADE
###############################################################################

    AUTO_UPGRADE=$(aws elasticache describe-cache-clusters \
        --cache-cluster-id "$CLUSTER" \
        --show-cache-node-info \
        --query 'CacheClusters[0].AutoMinorVersionUpgrade' \
        --output text 2>/dev/null)

    if [[ "$AUTO_UPGRADE" == "True" ]]
    then
        write_result "$REGION" ELASTICACHE AUTO_MINOR_VERSION_UPGRADE "$CLUSTER" PASS LOW \
        "Auto minor version upgrade enabled"
    else
        write_result "$REGION" ELASTICACHE AUTO_MINOR_VERSION_UPGRADE "$CLUSTER" FAIL LOW \
        "Auto minor version upgrade disabled"
    fi

###############################################################################
# CLUSTER STATUS
###############################################################################

    STATUS=$(aws elasticache describe-cache-clusters \
        --cache-cluster-id "$CLUSTER" \
        --show-cache-node-info \
        --query 'CacheClusters[0].CacheClusterStatus' \
        --output text 2>/dev/null)

    if [[ "$STATUS" == "available" ]]
    then
        write_result "$REGION" ELASTICACHE CLUSTER_STATUS "$CLUSTER" PASS LOW \
        "Cluster available"
    else
        write_result "$REGION" ELASTICACHE CLUSTER_STATUS "$CLUSTER" FAIL LOW \
        "Cluster status: $STATUS"
    fi

###############################################################################
# CLUSTER TAGS
###############################################################################

    CLUSTER_ARN=$(aws elasticache describe-cache-clusters \
        --cache-cluster-id "$CLUSTER" \
        --show-cache-node-info \
        --query 'CacheClusters[0].ARN' \
        --output text 2>/dev/null)

    TAGS=$(aws elasticache list-tags-for-resource \
        --resource-name "$CLUSTER_ARN" \
        --query 'TagList[*].Key' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" ELASTICACHE CLUSTER_TAGS "$CLUSTER" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" ELASTICACHE CLUSTER_TAGS "$CLUSTER" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# KMS KEY
###############################################################################

    KMS_KEY=$(aws elasticache describe-cache-clusters \
        --cache-cluster-id "$CLUSTER" \
        --show-cache-node-info \
        --query 'CacheClusters[0].KmsKeyId' \
        --output text 2>/dev/null)

    if [[ -n "$KMS_KEY" && "$KMS_KEY" != "None" ]]
    then
        write_result "$REGION" ELASTICACHE KMS_KEY "$CLUSTER" PASS LOW \
        "Customer-managed KMS key configured"
    else
        write_result "$REGION" ELASTICACHE KMS_KEY "$CLUSTER" FAIL LOW \
        "AWS-managed key or no KMS key configured"
    fi

###############################################################################
# ENGINE VERSION
###############################################################################

    ENGINE=$(aws elasticache describe-cache-clusters \
        --cache-cluster-id "$CLUSTER" \
        --show-cache-node-info \
        --query 'CacheClusters[0].EngineVersion' \
        --output text 2>/dev/null)

    if [[ -n "$ENGINE" && "$ENGINE" != "None" ]]
    then
        write_result "$REGION" ELASTICACHE ENGINE_VERSION "$CLUSTER" PASS LOW \
        "Engine version: $ENGINE"
    else
        write_result "$REGION" ELASTICACHE ENGINE_VERSION "$CLUSTER" FAIL LOW \
        "Engine version unavailable"
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
    ELASTICACHE \
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
echo "ElastiCache Audit Complete"
