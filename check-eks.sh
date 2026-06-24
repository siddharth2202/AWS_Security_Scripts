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

SERVICE="EKS"

create_report_dir

REPORT_FILE="reports/eks-report.csv"
HTML_FILE="reports/eks-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# EKS CLUSTERS
###############################################################################

EKS_CLUSTERS=$(aws eks list-clusters \
    --query 'clusters[*]' \
    --output text 2>/dev/null)

for EKS_CLUSTER in $EKS_CLUSTERS
do

    REGION="$DEFAULT_REGION"

###############################################################################
# PRIVATE ENDPOINT
###############################################################################

    PRIVATE=$(aws eks describe-cluster \
        --name "$EKS_CLUSTER" \
        --query 'cluster.resourcesVpcConfig.endpointPrivateAccess' \
        --output text 2>/dev/null)

    if [[ "$PRIVATE" == "True" ]]
    then
        write_result "$REGION" EKS EKS_PRIVATE_ENDPOINT "$EKS_CLUSTER" PASS HIGH \
        "Private endpoint enabled"
    else
        write_result "$REGION" EKS EKS_PRIVATE_ENDPOINT "$EKS_CLUSTER" FAIL HIGH \
        "Private endpoint disabled"
    fi

###############################################################################
# PUBLIC ENDPOINT
###############################################################################

    PUBLIC=$(aws eks describe-cluster \
        --name "$EKS_CLUSTER" \
        --query 'cluster.resourcesVpcConfig.endpointPublicAccess' \
        --output text 2>/dev/null)

    if [[ "$PUBLIC" == "True" ]]
    then
        write_result "$REGION" EKS EKS_PUBLIC_ENDPOINT "$EKS_CLUSTER" FAIL HIGH \
        "Public endpoint enabled"
    else
        write_result "$REGION" EKS EKS_PUBLIC_ENDPOINT "$EKS_CLUSTER" PASS HIGH \
        "Public endpoint disabled"
    fi

###############################################################################
# CLUSTER LOGGING
###############################################################################

    LOGGING=$(aws eks describe-cluster \
        --name "$EKS_CLUSTER" \
        --query 'cluster.logging.clusterLogging[0].enabled' \
        --output text 2>/dev/null)

    if [[ "$LOGGING" == "True" ]]
    then
        write_result "$REGION" EKS EKS_LOGGING "$EKS_CLUSTER" PASS MEDIUM \
        "Cluster logging enabled"
    else
        write_result "$REGION" EKS EKS_LOGGING "$EKS_CLUSTER" FAIL MEDIUM \
        "Cluster logging disabled"
    fi

###############################################################################
# SECRETS ENCRYPTION
###############################################################################

    ENCRYPTION=$(aws eks describe-cluster \
        --name "$EKS_CLUSTER" \
        --query 'cluster.encryptionConfig[*].provider.keyArn' \
        --output text 2>/dev/null)

    if [[ -n "$ENCRYPTION" && "$ENCRYPTION" != "None" ]]
    then
        write_result "$REGION" EKS EKS_ENCRYPTION "$EKS_CLUSTER" PASS HIGH \
        "Secrets encryption enabled"
    else
        write_result "$REGION" EKS EKS_ENCRYPTION "$EKS_CLUSTER" FAIL HIGH \
        "Secrets encryption disabled"
    fi

###############################################################################
# TAGS
###############################################################################

    TAGS=$(aws eks describe-cluster \
        --name "$EKS_CLUSTER" \
        --query 'cluster.tags' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" EKS EKS_TAGS "$EKS_CLUSTER" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" EKS EKS_TAGS "$EKS_CLUSTER" FAIL LOW \
        "No tags configured"
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
    EKS \
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
echo "EKS Audit Complete"
    
