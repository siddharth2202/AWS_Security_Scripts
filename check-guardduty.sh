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

SERVICE="GUARDDUTY"

create_report_dir

REPORT_FILE="reports/guardduty-report.csv"
HTML_FILE="reports/guardduty-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# DETECTORS
###############################################################################

DETECTORS=$(aws guardduty list-detectors \
    --query 'DetectorIds[*]' \
    --output text 2>/dev/null)

for DETECTOR in $DETECTORS
do

    REGION="$DEFAULT_REGION"

###############################################################################
# GUARDDUTY ENABLED
###############################################################################

    STATUS=$(aws guardduty get-detector \
        --detector-id "$DETECTOR" \
        --query 'Status' \
        --output text 2>/dev/null)

    if [[ "$STATUS" == "ENABLED" ]]
    then
        write_result "$REGION" GUARDDUTY GUARDDUTY_ENABLED "$DETECTOR" PASS CRITICAL \
        "GuardDuty enabled"
    else
        write_result "$REGION" GUARDDUTY GUARDDUTY_ENABLED "$DETECTOR" FAIL CRITICAL \
        "GuardDuty disabled"
    fi

###############################################################################
# FINDING PUBLISHING FREQUENCY
###############################################################################

    FREQ=$(aws guardduty get-detector \
        --detector-id "$DETECTOR" \
        --query 'FindingPublishingFrequency' \
        --output text 2>/dev/null)

    if [[ -n "$FREQ" && "$FREQ" != "None" ]]
    then
        write_result "$REGION" GUARDDUTY FINDING_FREQUENCY "$DETECTOR" PASS LOW \
        "$FREQ"
    else
        write_result "$REGION" GUARDDUTY FINDING_FREQUENCY "$DETECTOR" FAIL LOW \
        "Publishing frequency unavailable"
    fi

###############################################################################
# S3 PROTECTION
###############################################################################

    S3_PROTECTION=$(aws guardduty get-detector \
        --detector-id "$DETECTOR" \
        --query 'Features[?Name==`S3_DATA_EVENTS`].Status' \
        --output text 2>/dev/null)

    if [[ "$S3_PROTECTION" == "ENABLED" ]]
    then
        write_result "$REGION" GUARDDUTY S3_PROTECTION "$DETECTOR" PASS HIGH \
        "S3 Protection enabled"
    else
        write_result "$REGION" GUARDDUTY S3_PROTECTION "$DETECTOR" FAIL HIGH \
        "S3 Protection disabled"
    fi

###############################################################################
# EKS AUDIT LOGS
###############################################################################

    EKS=$(aws guardduty get-detector \
        --detector-id "$DETECTOR" \
        --query 'Features[?Name==`EKS_AUDIT_LOGS`].Status' \
        --output text 2>/dev/null)

    if [[ "$EKS" == "ENABLED" ]]
    then
        write_result "$REGION" GUARDDUTY EKS_AUDIT_LOGS "$DETECTOR" PASS HIGH \
        "EKS Protection enabled"
    else
        write_result "$REGION" GUARDDUTY EKS_AUDIT_LOGS "$DETECTOR" FAIL HIGH \
        "EKS Protection disabled"
    fi

###############################################################################
# EBS MALWARE PROTECTION
###############################################################################

    EBS=$(aws guardduty get-detector \
        --detector-id "$DETECTOR" \
        --query 'Features[?Name==`EBS_MALWARE_PROTECTION`].Status' \
        --output text 2>/dev/null)

    if [[ "$EBS" == "ENABLED" ]]
    then
        write_result "$REGION" GUARDDUTY EBS_MALWARE_PROTECTION "$DETECTOR" PASS HIGH \
        "Malware Protection enabled"
    else
        write_result "$REGION" GUARDDUTY EBS_MALWARE_PROTECTION "$DETECTOR" FAIL HIGH \
        "Malware Protection disabled"
    fi

###############################################################################
# RUNTIME MONITORING
###############################################################################

    RUNTIME=$(aws guardduty get-detector \
        --detector-id "$DETECTOR" \
        --query 'Features[?Name==`RUNTIME_MONITORING`].Status' \
        --output text 2>/dev/null)

    if [[ "$RUNTIME" == "ENABLED" ]]
    then
        write_result "$REGION" GUARDDUTY RUNTIME_MONITORING "$DETECTOR" PASS HIGH \
        "Runtime Monitoring enabled"
    else
        write_result "$REGION" GUARDDUTY RUNTIME_MONITORING "$DETECTOR" FAIL HIGH \
        "Runtime Monitoring disabled"
    fi

###############################################################################
# RDS LOGIN EVENTS
###############################################################################

    RDS=$(aws guardduty get-detector \
        --detector-id "$DETECTOR" \
        --query 'Features[?Name==`RDS_LOGIN_EVENTS`].Status' \
        --output text 2>/dev/null)

    if [[ "$RDS" == "ENABLED" ]]
    then
        write_result "$REGION" GUARDDUTY RDS_LOGIN_EVENTS "$DETECTOR" PASS MEDIUM \
        "RDS Login Events enabled"
    else
        write_result "$REGION" GUARDDUTY RDS_LOGIN_EVENTS "$DETECTOR" FAIL MEDIUM \
        "RDS Login Events disabled"
    fi

###############################################################################
# DETECTOR TAGS
###############################################################################

    TAGS=$(aws guardduty list-tags-for-resource \
        --resource-arn "$(aws guardduty get-detector \
            --detector-id "$DETECTOR" \
            --query 'Service.RoleArn' \
            --output text 2>/dev/null)" \
        --query 'Tags' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" GUARDDUTY DETECTOR_TAGS "$DETECTOR" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" GUARDDUTY DETECTOR_TAGS "$DETECTOR" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# PUBLISHING DESTINATION
###############################################################################

    DESTINATION=$(aws guardduty list-publishing-destinations \
        --detector-id "$DETECTOR" \
        --query 'Destinations[*].DestinationType' \
        --output text 2>/dev/null)

    if [[ -n "$DESTINATION" && "$DESTINATION" != "None" ]]
    then
        write_result "$REGION" GUARDDUTY PUBLISHING_DESTINATION "$DETECTOR" PASS LOW \
        "Publishing destination configured"
    else
        write_result "$REGION" GUARDDUTY PUBLISHING_DESTINATION "$DETECTOR" FAIL LOW \
        "No publishing destination"
    fi

###############################################################################
# DETECTOR STATUS
###############################################################################

    STATUS=$(aws guardduty get-detector \
        --detector-id "$DETECTOR" \
        --query 'Status' \
        --output text 2>/dev/null)

    if [[ "$STATUS" == "ENABLED" ]]
    then
        write_result "$REGION" GUARDDUTY DETECTOR_STATUS "$DETECTOR" PASS LOW \
        "Detector operational"
    else
        write_result "$REGION" GUARDDUTY DETECTOR_STATUS "$DETECTOR" FAIL LOW \
        "Detector not operational"
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
    GUARDDUTY \
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
echo "GuardDuty Audit Complete"
