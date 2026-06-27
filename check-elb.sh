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

SERVICE="ELB"

create_report_dir

REPORT_FILE="reports/elb-report.csv"
HTML_FILE="reports/elb-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# LOAD BALANCERS
###############################################################################

LOADBALANCERS=$(aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[*].LoadBalancerArn' \
    --output text 2>/dev/null)

for LB in $LOADBALANCERS
do

    REGION="$DEFAULT_REGION"

###############################################################################
# INTERNET FACING
###############################################################################

    SCHEME=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$LB" \
        --query 'LoadBalancers[0].Scheme' \
        --output text 2>/dev/null)

    if [[ "$SCHEME" == "internet-facing" ]]
    then
        write_result "$REGION" ELB INTERNET_FACING "$LB" PASS HIGH \
        "Internet-facing load balancer"
    else
        write_result "$REGION" ELB INTERNET_FACING "$LB" PASS LOW \
        "Internal load balancer"
    fi

###############################################################################
# HTTPS LISTENER
###############################################################################

    HTTPS=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$LB" \
        --query 'Listeners[?Protocol==`HTTPS`].Protocol' \
        --output text 2>/dev/null)

    if [[ -n "$HTTPS" ]]
    then
        write_result "$REGION" ELB HTTPS_LISTENER "$LB" PASS CRITICAL \
        "HTTPS listener configured"
    else
        write_result "$REGION" ELB HTTPS_LISTENER "$LB" FAIL CRITICAL \
        "No HTTPS listener"
    fi

###############################################################################
# TLS SECURITY POLICY
###############################################################################

    POLICY=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$LB" \
        --query 'Listeners[?Protocol==`HTTPS`].SslPolicy' \
        --output text 2>/dev/null)

    if [[ "$POLICY" == ELBSecurityPolicy-TLS* ]]
    then
        write_result "$REGION" ELB TLS_POLICY "$LB" PASS HIGH \
        "$POLICY"
    else
        write_result "$REGION" ELB TLS_POLICY "$LB" FAIL HIGH \
        "Weak or missing TLS policy"
    fi

###############################################################################
# DELETION PROTECTION
###############################################################################

    DELETE=$(aws elbv2 describe-load-balancer-attributes \
        --load-balancer-arn "$LB" \
        --query 'Attributes[?Key==`deletion_protection.enabled`].Value' \
        --output text 2>/dev/null)

    if [[ "$DELETE" == "true" ]]
    then
        write_result "$REGION" ELB DELETION_PROTECTION "$LB" PASS MEDIUM \
        "Deletion protection enabled"
    else
        write_result "$REGION" ELB DELETION_PROTECTION "$LB" FAIL MEDIUM \
        "Deletion protection disabled"
    fi

###############################################################################
# ACCESS LOGGING
###############################################################################

    LOGGING=$(aws elbv2 describe-load-balancer-attributes \
        --load-balancer-arn "$LB" \
        --query 'Attributes[?Key==`access_logs.s3.enabled`].Value' \
        --output text 2>/dev/null)

    if [[ "$LOGGING" == "true" ]]
    then
        write_result "$REGION" ELB ACCESS_LOGS "$LB" PASS MEDIUM \
        "Access logging enabled"
    else
        write_result "$REGION" ELB ACCESS_LOGS "$LB" FAIL MEDIUM \
        "Access logging disabled"
    fi

    ###############################################################################
# WAF ASSOCIATION
###############################################################################

    WAF=$(aws wafv2 get-web-acl-for-resource \
        --resource-arn "$LB" \
        --query 'WebACL.Name' \
        --output text 2>/dev/null)

    if [[ -n "$WAF" && "$WAF" != "None" ]]
    then
        write_result "$REGION" ELB WAF_ASSOCIATION "$LB" PASS HIGH \
        "Associated with WAF: $WAF"
    else
        write_result "$REGION" ELB WAF_ASSOCIATION "$LB" FAIL HIGH \
        "No WAF associated"
    fi

###############################################################################
# CROSS-ZONE LOAD BALANCING
###############################################################################

    CROSS_ZONE=$(aws elbv2 describe-load-balancer-attributes \
        --load-balancer-arn "$LB" \
        --query 'Attributes[?Key==`load_balancing.cross_zone.enabled`].Value' \
        --output text 2>/dev/null)

    if [[ "$CROSS_ZONE" == "true" ]]
    then
        write_result "$REGION" ELB CROSS_ZONE "$LB" PASS LOW \
        "Cross-zone load balancing enabled"
    else
        write_result "$REGION" ELB CROSS_ZONE "$LB" FAIL LOW \
        "Cross-zone load balancing disabled"
    fi

###############################################################################
# IDLE TIMEOUT
###############################################################################

    IDLE_TIMEOUT=$(aws elbv2 describe-load-balancer-attributes \
        --load-balancer-arn "$LB" \
        --query 'Attributes[?Key==`idle_timeout.timeout_seconds`].Value' \
        --output text 2>/dev/null)

    if [[ -n "$IDLE_TIMEOUT" && "$IDLE_TIMEOUT" != "None" ]]
    then
        write_result "$REGION" ELB IDLE_TIMEOUT "$LB" PASS LOW \
        "Idle timeout: ${IDLE_TIMEOUT}s"
    else
        write_result "$REGION" ELB IDLE_TIMEOUT "$LB" FAIL LOW \
        "Idle timeout unavailable"
    fi

###############################################################################
# LOAD BALANCER TAGS
###############################################################################

    TAGS=$(aws elbv2 describe-tags \
        --resource-arns "$LB" \
        --query 'TagDescriptions[0].Tags[*].Key' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" ELB LB_TAGS "$LB" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" ELB LB_TAGS "$LB" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# LOAD BALANCER STATUS
###############################################################################

    STATE=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$LB" \
        --query 'LoadBalancers[0].State.Code' \
        --output text 2>/dev/null)

    if [[ "$STATE" == "active" ]]
    then
        write_result "$REGION" ELB LB_STATUS "$LB" PASS LOW \
        "Load balancer active"
    else
        write_result "$REGION" ELB LB_STATUS "$LB" FAIL LOW \
        "State: $STATE"
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
    ELB \
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
echo "ELB / ALB / NLB Audit Complete"
