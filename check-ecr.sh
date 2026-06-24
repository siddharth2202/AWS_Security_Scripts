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

SERVICE="ECR"

create_report_dir

REPORT_FILE="reports/ecr-report.csv"
HTML_FILE="reports/ecr-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# REPOSITORIES
###############################################################################

REPOS=$(aws ecr describe-repositories \
    --query 'repositories[*].repositoryName' \
    --output text 2>/dev/null)

for REPO in $REPOS
do

    REGION="$DEFAULT_REGION"

###############################################################################
# IMAGE SCANNING
###############################################################################

    SCAN=$(aws ecr describe-repositories \
        --repository-names "$REPO" \
        --query 'repositories[0].imageScanningConfiguration.scanOnPush' \
        --output text 2>/dev/null)

    if [[ "$SCAN" == "True" ]]
    then
        write_result "$REGION" ECR IMAGE_SCANNING "$REPO" PASS HIGH \
        "Scan on push enabled"
    else
        write_result "$REGION" ECR IMAGE_SCANNING "$REPO" FAIL HIGH \
        "Scan on push disabled"
    fi

###############################################################################
# ENCRYPTION
###############################################################################

    ENCRYPTION=$(aws ecr describe-repositories \
        --repository-names "$REPO" \
        --query 'repositories[0].encryptionConfiguration.encryptionType' \
        --output text 2>/dev/null)

    if [[ "$ENCRYPTION" == "KMS" ]]
    then
        write_result "$REGION" ECR KMS_ENCRYPTION "$REPO" PASS HIGH \
        "KMS encryption enabled"
    else
        write_result "$REGION" ECR KMS_ENCRYPTION "$REPO" PASS HIGH \
        "AES256 encryption"
    fi

###############################################################################
# TAG IMMUTABILITY
###############################################################################

    IMMUTABLE=$(aws ecr describe-repositories \
        --repository-names "$REPO" \
        --query 'repositories[0].imageTagMutability' \
        --output text 2>/dev/null)

    if [[ "$IMMUTABLE" == "IMMUTABLE" ]]
    then
        write_result "$REGION" ECR IMMUTABLE_TAGS "$REPO" PASS MEDIUM \
        "Tag immutability enabled"
    else
        write_result "$REGION" ECR IMMUTABLE_TAGS "$REPO" FAIL MEDIUM \
        "Tag mutability enabled"
    fi

###############################################################################
# LIFECYCLE POLICY
###############################################################################

    POLICY=$(aws ecr get-lifecycle-policy \
        --repository-name "$REPO" \
        --query 'lifecyclePolicyText' \
        --output text 2>/dev/null)

    if [[ -n "$POLICY" && "$POLICY" != "None" ]]
    then
        write_result "$REGION" ECR LIFECYCLE_POLICY "$REPO" PASS LOW \
        "Lifecycle policy configured"
    else
        write_result "$REGION" ECR LIFECYCLE_POLICY "$REPO" FAIL LOW \
        "Lifecycle policy missing"
    fi

###############################################################################
# REPOSITORY POLICY
###############################################################################

    REPO_POLICY=$(aws ecr get-repository-policy \
        --repository-name "$REPO" \
        --query 'policyText' \
        --output text 2>/dev/null)

    if [[ -n "$REPO_POLICY" && "$REPO_POLICY" != "None" ]]
    then
        write_result "$REGION" ECR REPOSITORY_POLICY "$REPO" PASS MEDIUM \
        "Repository policy configured"
    else
        write_result "$REGION" ECR REPOSITORY_POLICY "$REPO" FAIL MEDIUM \
        "Repository policy missing"
    fi

###############################################################################
# PUBLIC ACCESS
###############################################################################

    REPO_POLICY=$(aws ecr get-repository-policy \
        --repository-name "$REPO" \
        --query 'policyText' \
        --output text 2>/dev/null)

    if echo "$REPO_POLICY" | grep -q '"Principal":"\*"'
    then
        write_result "$REGION" ECR PUBLIC_ACCESS "$REPO" FAIL CRITICAL \
        "Repository publicly accessible"
    else
        write_result "$REGION" ECR PUBLIC_ACCESS "$REPO" PASS CRITICAL \
        "No public access detected"
    fi

###############################################################################
# IMAGE COUNT
###############################################################################

    IMAGE_COUNT=$(aws ecr describe-images \
        --repository-name "$REPO" \
        --query 'length(imageDetails)' \
        --output text 2>/dev/null)

    if [[ "$IMAGE_COUNT" -gt 0 ]]
    then
        write_result "$REGION" ECR IMAGE_COUNT "$REPO" PASS LOW \
        "$IMAGE_COUNT images present"
    else
        write_result "$REGION" ECR IMAGE_COUNT "$REPO" FAIL LOW \
        "No images present"
    fi

###############################################################################
# TAGS
###############################################################################

    TAGS=$(aws ecr list-tags-for-resource \
        --resource-arn "$(aws ecr describe-repositories \
            --repository-names "$REPO" \
            --query 'repositories[0].repositoryArn' \
            --output text 2>/dev/null)" \
        --query 'tags[*].Key' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" ECR TAGS_PRESENT "$REPO" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" ECR TAGS_PRESENT "$REPO" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# PULL THROUGH CACHE
###############################################################################

    CACHE_RULES=$(aws ecr describe-pull-through-cache-rules \
        --query 'pullThroughCacheRules[*].ecrRepositoryPrefix' \
        --output text 2>/dev/null)

    if [[ -n "$CACHE_RULES" ]]
    then
        write_result "$REGION" ECR PULL_THROUGH_CACHE "$REPO" PASS LOW \
        "Pull-through cache configured"
    else
        write_result "$REGION" ECR PULL_THROUGH_CACHE "$REPO" FAIL LOW \
        "No pull-through cache rules"
    fi

###############################################################################
# REPLICATION
###############################################################################

    REPLICATION=$(aws ecr describe-registry \
        --query 'replicationConfiguration.rules' \
        --output text 2>/dev/null)

    if [[ -n "$REPLICATION" && "$REPLICATION" != "None" ]]
    then
        write_result "$REGION" ECR REPLICATION "$REPO" PASS LOW \
        "Replication configured"
    else
        write_result "$REGION" ECR REPLICATION "$REPO" FAIL LOW \
        "Replication not configured"
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
    ECR \
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
echo "ECR Audit Complete"
