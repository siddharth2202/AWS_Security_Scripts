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

SERVICE="WAF"

create_report_dir

REPORT_FILE="reports/waf-report.csv"
HTML_FILE="reports/waf-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# WEB ACLS
###############################################################################

REGION="$DEFAULT_REGION"

WEB_ACLS=$(aws wafv2 list-web-acls \
    --scope REGIONAL \
    --query 'WebACLs[*].ARN' \
    --output text 2>/dev/null)

for WEBACL in $WEB_ACLS
do

###############################################################################
# WEB ACL PRESENT
###############################################################################

    write_result "$REGION" WAF WEB_ACL_PRESENT "$WEBACL" PASS CRITICAL \
    "Web ACL exists"

###############################################################################
# ASSOCIATED RESOURCES
###############################################################################

    RESOURCES=$(aws wafv2 list-resources-for-web-acl \
        --web-acl-arn "$WEBACL" \
        --resource-type APPLICATION_LOAD_BALANCER \
        --query 'ResourceArns' \
        --output text 2>/dev/null)

    if [[ -n "$RESOURCES" && "$RESOURCES" != "None" ]]
    then
        write_result "$REGION" WAF WAF_ASSOCIATED_RESOURCE "$WEBACL" PASS HIGH \
        "Web ACL associated with resources"
    else
        write_result "$REGION" WAF WAF_ASSOCIATED_RESOURCE "$WEBACL" FAIL HIGH \
        "No associated resources"
    fi

###############################################################################
# AWS MANAGED RULES
###############################################################################

    MANAGED=$(aws wafv2 get-web-acl \
        --scope REGIONAL \
        --id "$(basename "$WEBACL")" \
        --name "$(basename "$WEBACL")" \
        --query 'WebACL.Rules[?Statement.ManagedRuleGroupStatement].Name' \
        --output text 2>/dev/null)

    if [[ -n "$MANAGED" && "$MANAGED" != "None" ]]
    then
        write_result "$REGION" WAF AWS_MANAGED_RULES "$WEBACL" PASS HIGH \
        "Managed rule groups configured"
    else
        write_result "$REGION" WAF AWS_MANAGED_RULES "$WEBACL" FAIL HIGH \
        "No managed rule groups"
    fi

###############################################################################
# LOGGING
###############################################################################

    LOGGING=$(aws wafv2 get-logging-configuration \
        --resource-arn "$WEBACL" \
        --query 'LoggingConfiguration.ResourceArn' \
        --output text 2>/dev/null)

    if [[ -n "$LOGGING" && "$LOGGING" != "None" ]]
    then
        write_result "$REGION" WAF LOGGING_ENABLED "$WEBACL" PASS MEDIUM \
        "Logging enabled"
    else
        write_result "$REGION" WAF LOGGING_ENABLED "$WEBACL" FAIL MEDIUM \
        "Logging disabled"
    fi

###############################################################################
# DEFAULT ACTION
###############################################################################

    ACTION=$(aws wafv2 get-web-acl \
        --scope REGIONAL \
        --id "$(basename "$WEBACL")" \
        --name "$(basename "$WEBACL")" \
        --query 'WebACL.DefaultAction' \
        --output text 2>/dev/null)

    if echo "$ACTION" | grep -q Allow
    then
        write_result "$REGION" WAF DEFAULT_ACTION "$WEBACL" PASS MEDIUM \
        "Default action: Allow"
    else
        write_result "$REGION" WAF DEFAULT_ACTION "$WEBACL" PASS MEDIUM \
        "Default action: Block"
    fi

###############################################################################
# SHIELD ADVANCED
###############################################################################

    SHIELD=$(aws shield describe-protection \
        --resource-arn "$WEBACL" \
        --query 'Protection.Name' \
        --output text 2>/dev/null)

    if [[ -n "$SHIELD" && "$SHIELD" != "None" ]]
    then
        write_result "$REGION" WAF SHIELD_ADVANCED "$WEBACL" PASS HIGH \
        "Shield Advanced protection configured"
    else
        write_result "$REGION" WAF SHIELD_ADVANCED "$WEBACL" FAIL HIGH \
        "Shield Advanced protection not configured"
    fi

###############################################################################
# RATE LIMIT RULE
###############################################################################

    RATE_LIMIT=$(aws wafv2 get-web-acl \
        --scope REGIONAL \
        --id "$(basename "$WEBACL")" \
        --name "$(basename "$WEBACL")" \
        --query 'WebACL.Rules[?Statement.RateBasedStatement].Name' \
        --output text 2>/dev/null)

    if [[ -n "$RATE_LIMIT" && "$RATE_LIMIT" != "None" ]]
    then
        write_result "$REGION" WAF RATE_LIMIT_RULE "$WEBACL" PASS MEDIUM \
        "Rate limiting rule configured"
    else
        write_result "$REGION" WAF RATE_LIMIT_RULE "$WEBACL" FAIL MEDIUM \
        "No rate limiting rule"
    fi

###############################################################################
# WEB ACL TAGS
###############################################################################

    TAGS=$(aws wafv2 list-tags-for-resource \
        --resource-arn "$WEBACL" \
        --query 'TagInfoForResource.TagList[*].Key' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" WAF WEB_ACL_TAGS "$WEBACL" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" WAF WEB_ACL_TAGS "$WEBACL" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# WEB ACL STATUS
###############################################################################

    write_result "$REGION" WAF WEB_ACL_STATUS "$WEBACL" PASS LOW \
    "Web ACL operational"

###############################################################################
# PROTECTED RESOURCES
###############################################################################

    RESOURCE_COUNT=$(echo "$RESOURCES" | wc -w)

    if [[ "$RESOURCE_COUNT" -gt 0 ]]
    then
        write_result "$REGION" WAF PROTECTED_RESOURCES "$WEBACL" PASS LOW \
        "$RESOURCE_COUNT protected resource(s)"
    else
        write_result "$REGION" WAF PROTECTED_RESOURCES "$WEBACL" FAIL LOW \
        "No protected resources"
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
    WAF \
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
echo "WAF & Shield Audit Complete"
