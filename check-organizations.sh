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

SERVICE="ORGANIZATIONS"

create_report_dir

REPORT_FILE="reports/organizations-report.csv"
HTML_FILE="reports/organizations-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# ORGANIZATION
###############################################################################

REGION="Global"

ORG_ID=$(aws organizations describe-organization \
    --query 'Organization.Id' \
    --output text 2>/dev/null)

if [[ -n "$ORG_ID" && "$ORG_ID" != "None" ]]
then

###############################################################################
# ORGANIZATIONS ENABLED
###############################################################################

    write_result "$REGION" ORGANIZATIONS ORGANIZATIONS_ENABLED "$ORG_ID" PASS CRITICAL \
    "AWS Organizations enabled"

###############################################################################
# ALL FEATURES
###############################################################################

    FEATURE_SET=$(aws organizations describe-organization \
        --query 'Organization.FeatureSet' \
        --output text 2>/dev/null)

    if [[ "$FEATURE_SET" == "ALL" ]]
    then
        write_result "$REGION" ORGANIZATIONS ALL_FEATURES_ENABLED "$ORG_ID" PASS HIGH \
        "All features enabled"
    else
        write_result "$REGION" ORGANIZATIONS ALL_FEATURES_ENABLED "$ORG_ID" FAIL HIGH \
        "Consolidated billing mode"
    fi

###############################################################################
# SERVICE CONTROL POLICIES
###############################################################################

    SCP=$(aws organizations list-roots \
        --query 'Roots[0].PolicyTypes[?Type==`SERVICE_CONTROL_POLICY`].Status' \
        --output text 2>/dev/null)

    if [[ "$SCP" == "ENABLED" ]]
    then
        write_result "$REGION" ORGANIZATIONS SCP_ENABLED "$ORG_ID" PASS HIGH \
        "Service Control Policies enabled"
    else
        write_result "$REGION" ORGANIZATIONS SCP_ENABLED "$ORG_ID" FAIL HIGH \
        "Service Control Policies disabled"
    fi

###############################################################################
# BACKUP POLICY
###############################################################################

    BACKUP=$(aws organizations list-roots \
        --query 'Roots[0].PolicyTypes[?Type==`BACKUP_POLICY`].Status' \
        --output text 2>/dev/null)

    if [[ "$BACKUP" == "ENABLED" ]]
    then
        write_result "$REGION" ORGANIZATIONS BACKUP_POLICY_ENABLED "$ORG_ID" PASS MEDIUM \
        "Backup policies enabled"
    else
        write_result "$REGION" ORGANIZATIONS BACKUP_POLICY_ENABLED "$ORG_ID" FAIL MEDIUM \
        "Backup policies disabled"
    fi

###############################################################################
# TAG POLICIES
###############################################################################

    TAG_POLICY=$(aws organizations list-roots \
        --query 'Roots[0].PolicyTypes[?Type==`TAG_POLICY`].Status' \
        --output text 2>/dev/null)

    if [[ "$TAG_POLICY" == "ENABLED" ]]
    then
        write_result "$REGION" ORGANIZATIONS TAG_POLICY_ENABLED "$ORG_ID" PASS MEDIUM \
        "Tag policies enabled"
    else
        write_result "$REGION" ORGANIZATIONS TAG_POLICY_ENABLED "$ORG_ID" FAIL MEDIUM \
        "Tag policies disabled"
    fi

    ###############################################################################
# AI SERVICES OPT-OUT POLICY
###############################################################################

    AI_POLICY=$(aws organizations list-roots \
        --query 'Roots[0].PolicyTypes[?Type==`AISERVICES_OPT_OUT_POLICY`].Status' \
        --output text 2>/dev/null)

    if [[ "$AI_POLICY" == "ENABLED" ]]
    then
        write_result "$REGION" ORGANIZATIONS AISERVICES_POLICY "$ORG_ID" PASS LOW \
        "AI Services Opt-Out Policy enabled"
    else
        write_result "$REGION" ORGANIZATIONS AISERVICES_POLICY "$ORG_ID" FAIL LOW \
        "AI Services Opt-Out Policy disabled"
    fi

###############################################################################
# ROOT OU COUNT
###############################################################################

    ROOT_COUNT=$(aws organizations list-roots \
        --query 'length(Roots)' \
        --output text 2>/dev/null)

    if [[ "$ROOT_COUNT" -gt 0 ]]
    then
        write_result "$REGION" ORGANIZATIONS ROOT_OU_COUNT "$ORG_ID" PASS LOW \
        "$ROOT_COUNT root OU(s)"
    else
        write_result "$REGION" ORGANIZATIONS ROOT_OU_COUNT "$ORG_ID" FAIL LOW \
        "No root OU found"
    fi

###############################################################################
# ACCOUNT COUNT
###############################################################################

    ACCOUNT_COUNT=$(aws organizations list-accounts \
        --query 'length(Accounts)' \
        --output text 2>/dev/null)

    if [[ "$ACCOUNT_COUNT" -gt 0 ]]
    then
        write_result "$REGION" ORGANIZATIONS ACCOUNT_COUNT "$ORG_ID" PASS LOW \
        "$ACCOUNT_COUNT account(s)"
    else
        write_result "$REGION" ORGANIZATIONS ACCOUNT_COUNT "$ORG_ID" FAIL LOW \
        "No accounts found"
    fi

###############################################################################
# DELEGATED ADMINISTRATORS
###############################################################################

    DELEGATED=$(aws organizations list-delegated-administrators \
        --query 'length(DelegatedAdministrators)' \
        --output text 2>/dev/null)

    if [[ "$DELEGATED" -ge 0 ]]
    then
        write_result "$REGION" ORGANIZATIONS DELEGATED_ADMIN "$ORG_ID" PASS LOW \
        "$DELEGATED delegated administrator(s)"
    else
        write_result "$REGION" ORGANIZATIONS DELEGATED_ADMIN "$ORG_ID" FAIL LOW \
        "Unable to retrieve delegated administrators"
    fi

###############################################################################
# ORGANIZATION STATUS
###############################################################################

    MASTER_ACCOUNT=$(aws organizations describe-organization \
        --query 'Organization.MasterAccountId' \
        --output text 2>/dev/null)

    if [[ -n "$MASTER_ACCOUNT" && "$MASTER_ACCOUNT" != "None" ]]
    then
        write_result "$REGION" ORGANIZATIONS ORGANIZATION_STATUS "$ORG_ID" PASS LOW \
        "Organization operational"
    else
        write_result "$REGION" ORGANIZATIONS ORGANIZATION_STATUS "$ORG_ID" FAIL LOW \
        "Organization status unavailable"
    fi

else

    write_result "$REGION" ORGANIZATIONS ORGANIZATIONS_ENABLED None FAIL CRITICAL \
    "AWS Organizations is not enabled"

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
    ORGANIZATIONS \
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
echo "AWS Organizations Audit Complete"
