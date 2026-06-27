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

SERVICE="INSPECTOR"

create_report_dir

REPORT_FILE="reports/inspector-report.csv"
HTML_FILE="reports/inspector-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# INSPECTOR CONFIGURATION
###############################################################################

REGION="$DEFAULT_REGION"

ACCOUNT_STATUS=$(aws inspector2 batch-get-account-status \
    --account-ids "$ACCOUNT_ID" \
    --query 'accounts[0].state.status' \
    --output text 2>/dev/null)

if [[ "$ACCOUNT_STATUS" == "ENABLED" ]]
then

###############################################################################
# INSPECTOR ENABLED
###############################################################################

    write_result "$REGION" INSPECTOR INSPECTOR_ENABLED "$ACCOUNT_ID" PASS CRITICAL \
    "Amazon Inspector enabled"

###############################################################################
# EC2 SCANNING
###############################################################################

    EC2=$(aws inspector2 batch-get-account-status \
        --account-ids "$ACCOUNT_ID" \
        --query 'accounts[0].resourceState.ec2.status' \
        --output text 2>/dev/null)

    if [[ "$EC2" == "ENABLED" ]]
    then
        write_result "$REGION" INSPECTOR EC2_SCANNING "$ACCOUNT_ID" PASS HIGH \
        "EC2 scanning enabled"
    else
        write_result "$REGION" INSPECTOR EC2_SCANNING "$ACCOUNT_ID" FAIL HIGH \
        "EC2 scanning disabled"
    fi

###############################################################################
# ECR SCANNING
###############################################################################

    ECR=$(aws inspector2 batch-get-account-status \
        --account-ids "$ACCOUNT_ID" \
        --query 'accounts[0].resourceState.ecr.status' \
        --output text 2>/dev/null)

    if [[ "$ECR" == "ENABLED" ]]
    then
        write_result "$REGION" INSPECTOR ECR_SCANNING "$ACCOUNT_ID" PASS HIGH \
        "ECR scanning enabled"
    else
        write_result "$REGION" INSPECTOR ECR_SCANNING "$ACCOUNT_ID" FAIL HIGH \
        "ECR scanning disabled"
    fi

###############################################################################
# LAMBDA SCANNING
###############################################################################

    LAMBDA=$(aws inspector2 batch-get-account-status \
        --account-ids "$ACCOUNT_ID" \
        --query 'accounts[0].resourceState.lambda.status' \
        --output text 2>/dev/null)

    if [[ "$LAMBDA" == "ENABLED" ]]
    then
        write_result "$REGION" INSPECTOR LAMBDA_SCANNING "$ACCOUNT_ID" PASS HIGH \
        "Lambda scanning enabled"
    else
        write_result "$REGION" INSPECTOR LAMBDA_SCANNING "$ACCOUNT_ID" FAIL HIGH \
        "Lambda scanning disabled"
    fi

###############################################################################
# CODE REPOSITORY SCANNING
###############################################################################

    CODE=$(aws inspector2 batch-get-account-status \
        --account-ids "$ACCOUNT_ID" \
        --query 'accounts[0].resourceState.codeRepository.status' \
        --output text 2>/dev/null)

    if [[ "$CODE" == "ENABLED" ]]
    then
        write_result "$REGION" INSPECTOR CODE_REPOSITORY_SCANNING "$ACCOUNT_ID" PASS MEDIUM \
        "Code repository scanning enabled"
    else
        write_result "$REGION" INSPECTOR CODE_REPOSITORY_SCANNING "$ACCOUNT_ID" FAIL MEDIUM \
        "Code repository scanning disabled"
    fi

else

    write_result "$REGION" INSPECTOR INSPECTOR_ENABLED "$ACCOUNT_ID" FAIL CRITICAL \
    "Amazon Inspector is not enabled"

fi

###############################################################################
# ACTIVE FINDINGS
###############################################################################

    FINDINGS=$(aws inspector2 list-findings \
        --query 'length(findings)' \
        --output text 2>/dev/null)

    if [[ "$FINDINGS" -ge 0 ]]
    then
        write_result "$REGION" INSPECTOR ACTIVE_FINDINGS "$ACCOUNT_ID" PASS MEDIUM \
        "$FINDINGS active finding(s)"
    else
        write_result "$REGION" INSPECTOR ACTIVE_FINDINGS "$ACCOUNT_ID" FAIL MEDIUM \
        "Unable to retrieve findings"
    fi

###############################################################################
# COVERAGE STATUS
###############################################################################

    COVERAGE=$(aws inspector2 list-coverage \
        --query 'length(coveredResources)' \
        --output text 2>/dev/null)

    if [[ "$COVERAGE" -gt 0 ]]
    then
        write_result "$REGION" INSPECTOR COVERAGE_STATUS "$ACCOUNT_ID" PASS LOW \
        "$COVERAGE resources covered"
    else
        write_result "$REGION" INSPECTOR COVERAGE_STATUS "$ACCOUNT_ID" FAIL LOW \
        "No covered resources"
    fi

###############################################################################
# RESOURCE COUNT
###############################################################################

    RESOURCE_COUNT=$(aws inspector2 list-coverage \
        --query 'length(coveredResources)' \
        --output text 2>/dev/null)

    if [[ "$RESOURCE_COUNT" -gt 0 ]]
    then
        write_result "$REGION" INSPECTOR RESOURCE_COUNT "$ACCOUNT_ID" PASS LOW \
        "$RESOURCE_COUNT resource(s) monitored"
    else
        write_result "$REGION" INSPECTOR RESOURCE_COUNT "$ACCOUNT_ID" FAIL LOW \
        "No monitored resources"
    fi

###############################################################################
# INSPECTOR STATUS
###############################################################################

    STATUS=$(aws inspector2 batch-get-account-status \
        --account-ids "$ACCOUNT_ID" \
        --query 'accounts[0].state.status' \
        --output text 2>/dev/null)

    if [[ "$STATUS" == "ENABLED" ]]
    then
        write_result "$REGION" INSPECTOR INSPECTOR_STATUS "$ACCOUNT_ID" PASS LOW \
        "Inspector operational"
    else
        write_result "$REGION" INSPECTOR INSPECTOR_STATUS "$ACCOUNT_ID" FAIL LOW \
        "Inspector not operational"
    fi

###############################################################################
# SCAN TYPE
###############################################################################

    SCAN_TYPES="EC2,ECR,LAMBDA,CODE_REPOSITORY"

    write_result "$REGION" INSPECTOR SCAN_TYPE "$ACCOUNT_ID" PASS LOW \
    "$SCAN_TYPES"

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
    INSPECTOR \
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
echo "Inspector Audit Complete"
