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

SERVICE="SECURITYHUB"

create_report_dir

REPORT_FILE="reports/securityhub-report.csv"
HTML_FILE="reports/securityhub-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# SECURITY HUB
###############################################################################

REGION="$DEFAULT_REGION"

HUB_ARN=$(aws securityhub describe-hub \
    --query 'HubArn' \
    --output text 2>/dev/null)

if [[ -n "$HUB_ARN" && "$HUB_ARN" != "None" ]]
then

###############################################################################
# SECURITY HUB ENABLED
###############################################################################

    write_result "$REGION" SECURITYHUB SECURITY_HUB_ENABLED "$HUB_ARN" PASS CRITICAL \
    "Security Hub enabled"

###############################################################################
# ENABLED STANDARDS
###############################################################################

    STANDARDS=$(aws securityhub get-enabled-standards \
        --query 'StandardsSubscriptions[*].StandardsArn' \
        --output text 2>/dev/null)

###############################################################################
# AWS FOUNDATIONAL SECURITY BEST PRACTICES
###############################################################################

    if echo "$STANDARDS" | grep -qi "aws-foundational-security-best-practices"
    then
        write_result "$REGION" SECURITYHUB AWS_FSBP_ENABLED "$HUB_ARN" PASS HIGH \
        "AWS Foundational Security Best Practices enabled"
    else
        write_result "$REGION" SECURITYHUB AWS_FSBP_ENABLED "$HUB_ARN" FAIL HIGH \
        "AWS Foundational Security Best Practices disabled"
    fi

###############################################################################
# CIS AWS FOUNDATIONS
###############################################################################

    if echo "$STANDARDS" | grep -qi "cis"
    then
        write_result "$REGION" SECURITYHUB CIS_STANDARD_ENABLED "$HUB_ARN" PASS HIGH \
        "CIS AWS Foundations enabled"
    else
        write_result "$REGION" SECURITYHUB CIS_STANDARD_ENABLED "$HUB_ARN" FAIL HIGH \
        "CIS AWS Foundations disabled"
    fi

###############################################################################
# PCI DSS
###############################################################################

    if echo "$STANDARDS" | grep -qi "pci"
    then
        write_result "$REGION" SECURITYHUB PCI_DSS_ENABLED "$HUB_ARN" PASS HIGH \
        "PCI DSS enabled"
    else
        write_result "$REGION" SECURITYHUB PCI_DSS_ENABLED "$HUB_ARN" FAIL HIGH \
        "PCI DSS disabled"
    fi

###############################################################################
# NIST
###############################################################################

    if echo "$STANDARDS" | grep -qi "nist"
    then
        write_result "$REGION" SECURITYHUB NIST_STANDARD_ENABLED "$HUB_ARN" PASS HIGH \
        "NIST standard enabled"
    else
        write_result "$REGION" SECURITYHUB NIST_STANDARD_ENABLED "$HUB_ARN" FAIL HIGH \
        "NIST standard disabled"
    fi

###############################################################################
# AUTO ENABLE CONTROLS
###############################################################################

    AUTO_ENABLE=$(aws securityhub describe-hub \
        --query 'AutoEnableControls' \
        --output text 2>/dev/null)

    if [[ "$AUTO_ENABLE" == "True" ]]
    then
        write_result "$REGION" SECURITYHUB AUTO_ENABLE_CONTROLS "$HUB_ARN" PASS MEDIUM \
        "Auto-enable controls enabled"
    else
        write_result "$REGION" SECURITYHUB AUTO_ENABLE_CONTROLS "$HUB_ARN" FAIL MEDIUM \
        "Auto-enable controls disabled"
    fi
else

    write_result "$REGION" SECURITYHUB SECURITY_HUB_ENABLED None FAIL CRITICAL \
    "Security Hub is not enabled"

fi

###############################################################################
# FINDINGS
###############################################################################

    FINDINGS=$(aws securityhub get-findings \
        --max-results 1 \
        --query 'Findings | length(@)' \
        --output text 2>/dev/null)

    if [[ "$FINDINGS" -ge 0 ]]
    then
        write_result "$REGION" SECURITYHUB CONTROL_FINDINGS "$HUB_ARN" PASS LOW \
        "Security Hub findings accessible"
    else
        write_result "$REGION" SECURITYHUB CONTROL_FINDINGS "$HUB_ARN" FAIL LOW \
        "Unable to retrieve findings"
    fi

###############################################################################
# HUB STATUS
###############################################################################

    HUB_STATUS=$(aws securityhub describe-hub \
        --query 'HubArn' \
        --output text 2>/dev/null)

    if [[ -n "$HUB_STATUS" && "$HUB_STATUS" != "None" ]]
    then
        write_result "$REGION" SECURITYHUB HUB_STATUS "$HUB_ARN" PASS LOW \
        "Hub operational"
    else
        write_result "$REGION" SECURITYHUB HUB_STATUS "$HUB_ARN" FAIL LOW \
        "Hub unavailable"
    fi

###############################################################################
# SECURITY SCORE
###############################################################################

    ACTIVE_FINDINGS=$(aws securityhub get-findings \
        --filters '{"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' \
        --query 'Findings | length(@)' \
        --output text 2>/dev/null)

    if [[ "$ACTIVE_FINDINGS" -eq 0 ]]
    then
        write_result "$REGION" SECURITYHUB SECURITY_SCORE "$HUB_ARN" PASS LOW \
        "No active findings"
    else
        write_result "$REGION" SECURITYHUB SECURITY_SCORE "$HUB_ARN" PASS LOW \
        "$ACTIVE_FINDINGS active findings"
    fi

###############################################################################
# HUB REGION
###############################################################################

    write_result "$REGION" SECURITYHUB HUB_REGION "$HUB_ARN" PASS LOW \
    "Security Hub configured in $REGION"

###############################################################################
# ENABLED STANDARDS COUNT
###############################################################################

    STANDARDS_COUNT=$(aws securityhub get-enabled-standards \
        --query 'length(StandardsSubscriptions)' \
        --output text 2>/dev/null)

    if [[ "$STANDARDS_COUNT" -gt 0 ]]
    then
        write_result "$REGION" SECURITYHUB ENABLED_STANDARDS_COUNT "$HUB_ARN" PASS LOW \
        "$STANDARDS_COUNT standards enabled"
    else
        write_result "$REGION" SECURITYHUB ENABLED_STANDARDS_COUNT "$HUB_ARN" FAIL LOW \
        "No standards enabled"
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
    SECURITYHUB \
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
echo "Security Hub Audit Complete"
