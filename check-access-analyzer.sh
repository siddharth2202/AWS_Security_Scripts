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

SERVICE="ACCESS_ANALYZER"

create_report_dir

REPORT_FILE="reports/access-analyzer-report.csv"
HTML_FILE="reports/access-analyzer-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# ACCESS ANALYZERS
###############################################################################

REGION="$DEFAULT_REGION"

ANALYZERS=$(aws accessanalyzer list-analyzers \
    --query 'analyzers[*].arn' \
    --output text 2>/dev/null)

for ANALYZER in $ANALYZERS
do

###############################################################################
# ACCESS ANALYZER ENABLED
###############################################################################

    STATUS=$(aws accessanalyzer get-analyzer \
        --analyzer-name "$(basename "$ANALYZER")" \
        --query 'status' \
        --output text 2>/dev/null)

    if [[ "$STATUS" == "ACTIVE" ]]
    then
        write_result "$REGION" ACCESS_ANALYZER ACCESS_ANALYZER_ENABLED "$ANALYZER" PASS CRITICAL \
        "Access Analyzer enabled"
    else
        write_result "$REGION" ACCESS_ANALYZER ACCESS_ANALYZER_ENABLED "$ANALYZER" FAIL CRITICAL \
        "Analyzer not active"
    fi

###############################################################################
# ACTIVE ANALYZER
###############################################################################

    if [[ "$STATUS" == "ACTIVE" ]]
    then
        write_result "$REGION" ACCESS_ANALYZER ACTIVE_ANALYZER "$ANALYZER" PASS HIGH \
        "Analyzer is active"
    else
        write_result "$REGION" ACCESS_ANALYZER ACTIVE_ANALYZER "$ANALYZER" FAIL HIGH \
        "Analyzer inactive"
    fi

###############################################################################
# EXTERNAL ACCESS FINDINGS
###############################################################################

    FINDINGS=$(aws accessanalyzer list-findings \
        --analyzer-name "$(basename "$ANALYZER")" \
        --filter '{"status":{"eq":["ACTIVE"]},"resourceType":{"exists":true}}' \
        --query 'findings | length(@)' \
        --output text 2>/dev/null)

    if [[ "$FINDINGS" -eq 0 ]]
    then
        write_result "$REGION" ACCESS_ANALYZER EXTERNAL_FINDINGS "$ANALYZER" PASS HIGH \
        "No active external access findings"
    else
        write_result "$REGION" ACCESS_ANALYZER EXTERNAL_FINDINGS "$ANALYZER" FAIL HIGH \
        "$FINDINGS active finding(s)"
    fi

###############################################################################
# UNUSED ACCESS FINDINGS
###############################################################################

    UNUSED=$(aws accessanalyzer list-findings-v2 \
        --analyzer-arn "$ANALYZER" \
        --query 'findings | length(@)' \
        --output text 2>/dev/null)

    if [[ "$UNUSED" -ge 0 ]]
    then
        write_result "$REGION" ACCESS_ANALYZER UNUSED_ACCESS_FINDINGS "$ANALYZER" PASS MEDIUM \
        "$UNUSED finding(s)"
    else
        write_result "$REGION" ACCESS_ANALYZER UNUSED_ACCESS_FINDINGS "$ANALYZER" FAIL MEDIUM \
        "Unable to retrieve findings"
    fi

###############################################################################
# ANALYZER TYPE
###############################################################################

    TYPE=$(aws accessanalyzer get-analyzer \
        --analyzer-name "$(basename "$ANALYZER")" \
        --query 'type' \
        --output text 2>/dev/null)

    if [[ -n "$TYPE" && "$TYPE" != "None" ]]
    then
        write_result "$REGION" ACCESS_ANALYZER ANALYZER_TYPE "$ANALYZER" PASS LOW \
        "$TYPE"
    else
        write_result "$REGION" ACCESS_ANALYZER ANALYZER_TYPE "$ANALYZER" FAIL LOW \
        "Analyzer type unavailable"
    fi

###############################################################################
# ANALYZER STATUS
###############################################################################

    STATUS=$(aws accessanalyzer get-analyzer \
        --analyzer-name "$(basename "$ANALYZER")" \
        --query 'status' \
        --output text 2>/dev/null)

    if [[ "$STATUS" == "ACTIVE" ]]
    then
        write_result "$REGION" ACCESS_ANALYZER ANALYZER_STATUS "$ANALYZER" PASS LOW \
        "Analyzer active"
    else
        write_result "$REGION" ACCESS_ANALYZER ANALYZER_STATUS "$ANALYZER" FAIL LOW \
        "Analyzer status: $STATUS"
    fi

###############################################################################
# TOTAL FINDINGS
###############################################################################

    TOTAL_FINDINGS=$(aws accessanalyzer list-findings \
        --analyzer-name "$(basename "$ANALYZER")" \
        --query 'length(findings)' \
        --output text 2>/dev/null)

    if [[ "$TOTAL_FINDINGS" -ge 0 ]]
    then
        write_result "$REGION" ACCESS_ANALYZER FINDING_COUNT "$ANALYZER" PASS LOW \
        "$TOTAL_FINDINGS finding(s)"
    else
        write_result "$REGION" ACCESS_ANALYZER FINDING_COUNT "$ANALYZER" FAIL LOW \
        "Unable to retrieve findings"
    fi

###############################################################################
# ARCHIVED FINDINGS
###############################################################################

    ARCHIVED=$(aws accessanalyzer list-findings \
        --analyzer-name "$(basename "$ANALYZER")" \
        --filter '{"status":{"eq":["ARCHIVED"]}}' \
        --query 'length(findings)' \
        --output text 2>/dev/null)

    if [[ "$ARCHIVED" -ge 0 ]]
    then
        write_result "$REGION" ACCESS_ANALYZER ARCHIVED_FINDINGS "$ANALYZER" PASS LOW \
        "$ARCHIVED archived finding(s)"
    else
        write_result "$REGION" ACCESS_ANALYZER ARCHIVED_FINDINGS "$ANALYZER" FAIL LOW \
        "Unable to retrieve archived findings"
    fi

###############################################################################
# ANALYZER TAGS
###############################################################################

    TAGS=$(aws accessanalyzer list-tags-for-resource \
        --resource-arn "$ANALYZER" \
        --query 'tags' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "{}" ]]
    then
        write_result "$REGION" ACCESS_ANALYZER ANALYZER_TAGS "$ANALYZER" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" ACCESS_ANALYZER ANALYZER_TAGS "$ANALYZER" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# REGION CONFIGURATION
###############################################################################

    write_result "$REGION" ACCESS_ANALYZER REGION_CONFIGURATION "$ANALYZER" PASS LOW \
    "Analyzer configured in $REGION"

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
    ACCESS_ANALYZER \
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
echo "Access Analyzer Audit Complete"
