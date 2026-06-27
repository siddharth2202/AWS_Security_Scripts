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

SERVICE="ROUTE53"

create_report_dir

REPORT_FILE="reports/route53-report.csv"
HTML_FILE="reports/route53-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# HOSTED ZONES
###############################################################################

HOSTED_ZONES=$(aws route53 list-hosted-zones \
    --query 'HostedZones[*].Id' \
    --output text 2>/dev/null)

for ZONE in $HOSTED_ZONES
do

    REGION="Global"

###############################################################################
# PUBLIC / PRIVATE HOSTED ZONE
###############################################################################

    PRIVATE=$(aws route53 get-hosted-zone \
        --id "$ZONE" \
        --query 'HostedZone.Config.PrivateZone' \
        --output text 2>/dev/null)

    if [[ "$PRIVATE" == "True" ]]
    then
        write_result "$REGION" ROUTE53 PRIVATE_HOSTED_ZONE "$ZONE" PASS LOW \
        "Private hosted zone"
    else
        write_result "$REGION" ROUTE53 PUBLIC_HOSTED_ZONE "$ZONE" PASS HIGH \
        "Public hosted zone"
    fi

###############################################################################
# DNSSEC
###############################################################################

    DNSSEC=$(aws route53 get-dnssec \
        --hosted-zone-id "$ZONE" \
        --query 'Status.ServeSignature' \
        --output text 2>/dev/null)

    if [[ "$DNSSEC" == "SIGNING" ]]
    then
        write_result "$REGION" ROUTE53 DNSSEC_ENABLED "$ZONE" PASS HIGH \
        "DNSSEC enabled"
    else
        write_result "$REGION" ROUTE53 DNSSEC_ENABLED "$ZONE" FAIL HIGH \
        "DNSSEC disabled"
    fi

###############################################################################
# QUERY LOGGING
###############################################################################

    QUERY_LOGGING=$(aws route53 list-query-logging-configs \
        --hosted-zone-id "$ZONE" \
        --query 'QueryLoggingConfigs[*].Id' \
        --output text 2>/dev/null)

    if [[ -n "$QUERY_LOGGING" && "$QUERY_LOGGING" != "None" ]]
    then
        write_result "$REGION" ROUTE53 QUERY_LOGGING "$ZONE" PASS MEDIUM \
        "Query logging enabled"
    else
        write_result "$REGION" ROUTE53 QUERY_LOGGING "$ZONE" FAIL MEDIUM \
        "Query logging disabled"
    fi

###############################################################################
# HEALTH CHECKS
###############################################################################

    HEALTH=$(aws route53 list-health-checks \
        --query 'HealthChecks | length(@)' \
        --output text 2>/dev/null)

    if [[ "$HEALTH" -gt 0 ]]
    then
        write_result "$REGION" ROUTE53 HEALTH_CHECKS "$ZONE" PASS LOW \
        "$HEALTH health checks configured"
    else
        write_result "$REGION" ROUTE53 HEALTH_CHECKS "$ZONE" FAIL LOW \
        "No health checks configured"
    fi

###############################################################################
# RECORD SET COUNT
###############################################################################

    RECORDS=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$ZONE" \
        --query 'length(ResourceRecordSets)' \
        --output text 2>/dev/null)

    if [[ "$RECORDS" -gt 0 ]]
    then
        write_result "$REGION" ROUTE53 RECORD_SETS "$ZONE" PASS LOW \
        "$RECORDS record sets"
    else
        write_result "$REGION" ROUTE53 RECORD_SETS "$ZONE" FAIL LOW \
        "No record sets"
    fi

###############################################################################
# HOSTED ZONE TAGS
###############################################################################

    TAGS=$(aws route53 list-tags-for-resource \
        --resource-type hostedzone \
        --resource-id "$(basename "$ZONE")" \
        --query 'ResourceTagSet.Tags[*].Key' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" ROUTE53 HOSTED_ZONE_TAGS "$ZONE" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" ROUTE53 HOSTED_ZONE_TAGS "$ZONE" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# REUSABLE DELEGATION SET
###############################################################################

    DELEGATION=$(aws route53 get-hosted-zone \
        --id "$ZONE" \
        --query 'DelegationSet.Id' \
        --output text 2>/dev/null)

    if [[ -n "$DELEGATION" && "$DELEGATION" != "None" ]]
    then
        write_result "$REGION" ROUTE53 REUSABLE_DELEGATION_SET "$ZONE" PASS LOW \
        "Delegation set configured"
    else
        write_result "$REGION" ROUTE53 REUSABLE_DELEGATION_SET "$ZONE" FAIL LOW \
        "No reusable delegation set"
    fi

###############################################################################
# VPC ASSOCIATION
###############################################################################

    VPCS=$(aws route53 get-hosted-zone \
        --id "$ZONE" \
        --query 'VPCs | length(@)' \
        --output text 2>/dev/null)

    if [[ "$PRIVATE" == "True" ]]
    then
        if [[ "$VPCS" -gt 0 ]]
        then
            write_result "$REGION" ROUTE53 VPC_ASSOCIATION "$ZONE" PASS LOW \
            "$VPCS VPC association(s)"
        else
            write_result "$REGION" ROUTE53 VPC_ASSOCIATION "$ZONE" FAIL LOW \
            "Private hosted zone has no VPC association"
        fi
    else
        write_result "$REGION" ROUTE53 VPC_ASSOCIATION "$ZONE" PASS LOW \
        "Not applicable for public hosted zone"
    fi

###############################################################################
# HOSTED ZONE STATUS
###############################################################################

    ZONE_NAME=$(aws route53 get-hosted-zone \
        --id "$ZONE" \
        --query 'HostedZone.Name' \
        --output text 2>/dev/null)

    if [[ -n "$ZONE_NAME" && "$ZONE_NAME" != "None" ]]
    then
        write_result "$REGION" ROUTE53 HOSTED_ZONE_STATUS "$ZONE" PASS LOW \
        "Hosted zone available"
    else
        write_result "$REGION" ROUTE53 HOSTED_ZONE_STATUS "$ZONE" FAIL LOW \
        "Unable to retrieve hosted zone"
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
    ROUTE53 \
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
echo "Route53 Audit Complete"
