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

SERVICE="REDSHIFT"

create_report_dir

REPORT_FILE="reports/redshift-report.csv"
HTML_FILE="reports/redshift-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# REDSHIFT CLUSTERS
###############################################################################

CLUSTERS=$(aws redshift describe-clusters \
    --query 'Clusters[*].ClusterIdentifier' \
    --output text 2>/dev/null)

for CLUSTER in $CLUSTERS
do

    REGION="$DEFAULT_REGION"

###############################################################################
# ENCRYPTION
###############################################################################

    ENCRYPTED=$(aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER" \
        --query 'Clusters[0].Encrypted' \
        --output text 2>/dev/null)

    if [[ "$ENCRYPTED" == "True" ]]
    then
        write_result "$REGION" REDSHIFT CLUSTER_ENCRYPTION "$CLUSTER" PASS CRITICAL \
        "Cluster encrypted"
    else
        write_result "$REGION" REDSHIFT CLUSTER_ENCRYPTION "$CLUSTER" FAIL CRITICAL \
        "Cluster not encrypted"
    fi

###############################################################################
# PUBLIC ACCESS
###############################################################################

    PUBLIC=$(aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER" \
        --query 'Clusters[0].PubliclyAccessible' \
        --output text 2>/dev/null)

    if [[ "$PUBLIC" == "True" ]]
    then
        write_result "$REGION" REDSHIFT PUBLIC_ACCESS "$CLUSTER" FAIL HIGH \
        "Cluster publicly accessible"
    else
        write_result "$REGION" REDSHIFT PUBLIC_ACCESS "$CLUSTER" PASS HIGH \
        "Cluster private"
    fi

###############################################################################
# AUTOMATED SNAPSHOTS
###############################################################################

    RETENTION=$(aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER" \
        --query 'Clusters[0].AutomatedSnapshotRetentionPeriod' \
        --output text 2>/dev/null)

    if [[ "$RETENTION" -gt 0 ]]
    then
        write_result "$REGION" REDSHIFT AUTOMATED_SNAPSHOTS "$CLUSTER" PASS HIGH \
        "$RETENTION day retention"
    else
        write_result "$REGION" REDSHIFT AUTOMATED_SNAPSHOTS "$CLUSTER" FAIL HIGH \
        "Automated snapshots disabled"
    fi

###############################################################################
# ENHANCED VPC ROUTING
###############################################################################

    VPC_ROUTING=$(aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER" \
        --query 'Clusters[0].EnhancedVpcRouting' \
        --output text 2>/dev/null)

    if [[ "$VPC_ROUTING" == "True" ]]
    then
        write_result "$REGION" REDSHIFT ENHANCED_VPC_ROUTING "$CLUSTER" PASS MEDIUM \
        "Enhanced VPC routing enabled"
    else
        write_result "$REGION" REDSHIFT ENHANCED_VPC_ROUTING "$CLUSTER" FAIL MEDIUM \
        "Enhanced VPC routing disabled"
    fi

###############################################################################
# KMS ENCRYPTION
###############################################################################

    KMS=$(aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER" \
        --query 'Clusters[0].KmsKeyId' \
        --output text 2>/dev/null)

    if [[ -n "$KMS" && "$KMS" != "None" ]]
    then
        write_result "$REGION" REDSHIFT KMS_ENCRYPTION "$CLUSTER" PASS HIGH \
        "KMS CMK configured"
    else
        write_result "$REGION" REDSHIFT KMS_ENCRYPTION "$CLUSTER" FAIL HIGH \
        "No KMS CMK configured"
    fi

    ###############################################################################
# LOGGING ENABLED
###############################################################################

    LOGGING=$(aws redshift describe-logging-status \
        --cluster-identifier "$CLUSTER" \
        --query 'LoggingEnabled' \
        --output text 2>/dev/null)

    if [[ "$LOGGING" == "true" || "$LOGGING" == "True" ]]
    then
        write_result "$REGION" REDSHIFT LOGGING_ENABLED "$CLUSTER" PASS MEDIUM \
        "Audit logging enabled"
    else
        write_result "$REGION" REDSHIFT LOGGING_ENABLED "$CLUSTER" FAIL MEDIUM \
        "Audit logging disabled"
    fi

###############################################################################
# MAINTENANCE TRACK
###############################################################################

    TRACK=$(aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER" \
        --query 'Clusters[0].MaintenanceTrackName' \
        --output text 2>/dev/null)

    if [[ -n "$TRACK" && "$TRACK" != "None" ]]
    then
        write_result "$REGION" REDSHIFT MAINTENANCE_TRACK "$CLUSTER" PASS LOW \
        "$TRACK"
    else
        write_result "$REGION" REDSHIFT MAINTENANCE_TRACK "$CLUSTER" FAIL LOW \
        "Maintenance track unavailable"
    fi

###############################################################################
# CLUSTER TAGS
###############################################################################

    TAGS=$(aws redshift describe-tags \
        --resource-name "$CLUSTER" \
        --query 'TaggedResources[*].Tag.Key' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" REDSHIFT CLUSTER_TAGS "$CLUSTER" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" REDSHIFT CLUSTER_TAGS "$CLUSTER" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# CLUSTER STATUS
###############################################################################

    STATUS=$(aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER" \
        --query 'Clusters[0].ClusterStatus' \
        --output text 2>/dev/null)

    if [[ "$STATUS" == "available" ]]
    then
        write_result "$REGION" REDSHIFT CLUSTER_STATUS "$CLUSTER" PASS LOW \
        "Cluster available"
    else
        write_result "$REGION" REDSHIFT CLUSTER_STATUS "$CLUSTER" FAIL LOW \
        "Cluster status: $STATUS"
    fi

###############################################################################
# IAM ROLES
###############################################################################

    IAM_ROLES=$(aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER" \
        --query 'Clusters[0].IamRoles[*].IamRoleArn' \
        --output text 2>/dev/null)

    if [[ -n "$IAM_ROLES" && "$IAM_ROLES" != "None" ]]
    then
        write_result "$REGION" REDSHIFT IAM_ROLES "$CLUSTER" PASS LOW \
        "IAM roles attached"
    else
        write_result "$REGION" REDSHIFT IAM_ROLES "$CLUSTER" FAIL LOW \
        "No IAM roles attached"
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
    REDSHIFT \
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
echo "Redshift Audit Complete"
