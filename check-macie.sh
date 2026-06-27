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

SERVICE="MACIE"

create_report_dir

REPORT_FILE="reports/macie-report.csv"
HTML_FILE="reports/macie-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# MACIE SESSION
###############################################################################

REGION="$DEFAULT_REGION"

STATUS=$(aws macie2 get-macie-session \
    --query 'status' \
    --output text 2>/dev/null)

if [[ "$STATUS" == "ENABLED" ]]
then

###############################################################################
# MACIE ENABLED
###############################################################################

    write_result "$REGION" MACIE MACIE_ENABLED Account PASS CRITICAL \
    "Macie enabled"

###############################################################################
# AUTOMATED DISCOVERY
###############################################################################

    AUTO_DISCOVERY=$(aws macie2 get-automated-discovery-configuration \
        --query 'classificationScopeId' \
        --output text 2>/dev/null)

    if [[ -n "$AUTO_DISCOVERY" && "$AUTO_DISCOVERY" != "None" ]]
    then
        write_result "$REGION" MACIE AUTOMATED_DISCOVERY Account PASS HIGH \
        "Automated discovery configured"
    else
        write_result "$REGION" MACIE AUTOMATED_DISCOVERY Account FAIL HIGH \
        "Automated discovery not configured"
    fi

###############################################################################
# CLASSIFICATION JOBS
###############################################################################

    JOBS=$(aws macie2 list-classification-jobs \
        --query 'items | length(@)' \
        --output text 2>/dev/null)

    if [[ "$JOBS" -gt 0 ]]
    then
        write_result "$REGION" MACIE CLASSIFICATION_JOBS Account PASS MEDIUM \
        "$JOBS classification jobs found"
    else
        write_result "$REGION" MACIE CLASSIFICATION_JOBS Account FAIL MEDIUM \
        "No classification jobs"
    fi

###############################################################################
# S3 BUCKETS MONITORED
###############################################################################

    BUCKETS=$(aws macie2 describe-buckets \
        --query 'buckets | length(@)' \
        --output text 2>/dev/null)

    if [[ "$BUCKETS" -gt 0 ]]
    then
        write_result "$REGION" MACIE S3_BUCKETS_MONITORED Account PASS MEDIUM \
        "$BUCKETS buckets monitored"
    else
        write_result "$REGION" MACIE S3_BUCKETS_MONITORED Account FAIL MEDIUM \
        "No monitored buckets"
    fi

###############################################################################
# FINDINGS AVAILABLE
###############################################################################

    FINDINGS=$(aws macie2 list-findings \
        --query 'findingIds | length(@)' \
        --output text 2>/dev/null)

    if [[ "$FINDINGS" -ge 0 ]]
    then
        write_result "$REGION" MACIE FINDINGS_AVAILABLE Account PASS LOW \
        "Findings accessible"
    else
        write_result "$REGION" MACIE FINDINGS_AVAILABLE Account FAIL LOW \
        "Unable to retrieve findings"
    fi

###############################################################################
# INVITATION STATUS
###############################################################################

    INVITATIONS=$(aws macie2 list-invitations \
        --query 'invitations | length(@)' \
        --output text 2>/dev/null)

    if [[ "$INVITATIONS" -ge 0 ]]
    then
        write_result "$REGION" MACIE INVITATION_STATUS Account PASS LOW \
        "Invitation information available"
    else
        write_result "$REGION" MACIE INVITATION_STATUS Account FAIL LOW \
        "Unable to retrieve invitations"
    fi

###############################################################################
# SESSION STATUS
###############################################################################

    SESSION_STATUS=$(aws macie2 get-macie-session \
        --query 'status' \
        --output text 2>/dev/null)

    if [[ "$SESSION_STATUS" == "ENABLED" ]]
    then
        write_result "$REGION" MACIE SESSION_STATUS Account PASS LOW \
        "Macie session active"
    else
        write_result "$REGION" MACIE SESSION_STATUS Account FAIL LOW \
        "Macie session inactive"
    fi

###############################################################################
# SERVICE LINKED ROLE
###############################################################################

    ROLE=$(aws iam get-role \
        --role-name AWSServiceRoleForAmazonMacie \
        --query 'Role.RoleName' \
        --output text 2>/dev/null)

    if [[ -n "$ROLE" && "$ROLE" != "None" ]]
    then
        write_result "$REGION" MACIE SERVICE_ROLE Account PASS LOW \
        "Service-linked role present"
    else
        write_result "$REGION" MACIE SERVICE_ROLE Account FAIL LOW \
        "Service-linked role not found"
    fi

###############################################################################
# LAST UPDATED
###############################################################################

    UPDATED=$(aws macie2 get-macie-session \
        --query 'updatedAt' \
        --output text 2>/dev/null)

    if [[ -n "$UPDATED" && "$UPDATED" != "None" ]]
    then
        write_result "$REGION" MACIE LAST_UPDATED Account PASS LOW \
        "Last updated: $UPDATED"
    else
        write_result "$REGION" MACIE LAST_UPDATED Account FAIL LOW \
        "Update time unavailable"
    fi

###############################################################################
# ACCOUNT STATUS
###############################################################################

    write_result "$REGION" MACIE ACCOUNT_STATUS Account PASS LOW \
    "Macie account operational"

else

    write_result "$REGION" MACIE MACIE_ENABLED Account FAIL CRITICAL \
    "Macie is not enabled"

fi

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
    MACIE \
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
echo "Macie Audit Complete"
