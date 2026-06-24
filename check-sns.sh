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

SERVICE="SNS"

create_report_dir

REPORT_FILE="reports/sns-report.csv"
HTML_FILE="reports/sns-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# SNS TOPICS
###############################################################################

TOPICS=$(aws sns list-topics \
    --query 'Topics[*].TopicArn' \
    --output text 2>/dev/null)

for TOPIC in $TOPICS
do

    REGION="$DEFAULT_REGION"

###############################################################################
# TOPIC ENCRYPTION
###############################################################################

    KMS_KEY=$(aws sns get-topic-attributes \
        --topic-arn "$TOPIC" \
        --query 'Attributes.KmsMasterKeyId' \
        --output text 2>/dev/null)

    if [[ -n "$KMS_KEY" && "$KMS_KEY" != "None" ]]
    then
        write_result "$REGION" SNS SNS_ENCRYPTION "$TOPIC" PASS HIGH \
        "KMS encryption enabled"
    else
        write_result "$REGION" SNS SNS_ENCRYPTION "$TOPIC" FAIL HIGH \
        "KMS encryption disabled"
    fi

###############################################################################
# ACCESS POLICY
###############################################################################

    POLICY=$(aws sns get-topic-attributes \
        --topic-arn "$TOPIC" \
        --query 'Attributes.Policy' \
        --output text 2>/dev/null)

    if [[ -n "$POLICY" && "$POLICY" != "None" ]]
    then
        write_result "$REGION" SNS SNS_POLICY "$TOPIC" PASS MEDIUM \
        "Access policy configured"
    else
        write_result "$REGION" SNS SNS_POLICY "$TOPIC" FAIL MEDIUM \
        "Access policy missing"
    fi

###############################################################################
# SUBSCRIPTIONS
###############################################################################

    SUBS=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$TOPIC" \
        --query 'Subscriptions[*].SubscriptionArn' \
        --output text 2>/dev/null)

    if [[ -n "$SUBS" && "$SUBS" != "None" ]]
    then
        write_result "$REGION" SNS SNS_SUBSCRIPTIONS "$TOPIC" PASS LOW \
        "Subscriptions configured"
    else
        write_result "$REGION" SNS SNS_SUBSCRIPTIONS "$TOPIC" FAIL LOW \
        "No subscriptions"
    fi

###############################################################################
# PENDING SUBSCRIPTIONS
###############################################################################

    PENDING=$(aws sns get-topic-attributes \
        --topic-arn "$TOPIC" \
        --query 'Attributes.SubscriptionsPending' \
        --output text 2>/dev/null)

    if [[ "$PENDING" -gt 0 ]]
    then
        write_result "$REGION" SNS SNS_PENDING_SUBSCRIPTIONS "$TOPIC" FAIL LOW \
        "Pending subscriptions: $PENDING"
    else
        write_result "$REGION" SNS SNS_PENDING_SUBSCRIPTIONS "$TOPIC" PASS LOW \
        "No pending subscriptions"
    fi

###############################################################################
# DELIVERY POLICY
###############################################################################

    DELIVERY=$(aws sns get-topic-attributes \
        --topic-arn "$TOPIC" \
        --query 'Attributes.DeliveryPolicy' \
        --output text 2>/dev/null)

    if [[ -n "$DELIVERY" && "$DELIVERY" != "None" ]]
    then
        write_result "$REGION" SNS SNS_DELIVERY_POLICY "$TOPIC" PASS LOW \
        "Delivery policy configured"
    else
        write_result "$REGION" SNS SNS_DELIVERY_POLICY "$TOPIC" FAIL LOW \
        "Delivery policy not configured"
    fi

###############################################################################
# DISPLAY NAME
###############################################################################

    DISPLAY_NAME=$(aws sns get-topic-attributes \
        --topic-arn "$TOPIC" \
        --query 'Attributes.DisplayName' \
        --output text 2>/dev/null)

    if [[ -n "$DISPLAY_NAME" && "$DISPLAY_NAME" != "None" ]]
    then
        write_result "$REGION" SNS SNS_DISPLAY_NAME "$TOPIC" PASS LOW \
        "Display name configured"
    else
        write_result "$REGION" SNS SNS_DISPLAY_NAME "$TOPIC" FAIL LOW \
        "Display name not configured"
    fi

###############################################################################
# FIFO TOPIC
###############################################################################

    FIFO=$(aws sns get-topic-attributes \
        --topic-arn "$TOPIC" \
        --query 'Attributes.FifoTopic' \
        --output text 2>/dev/null)

    if [[ "$FIFO" == "true" ]]
    then
        write_result "$REGION" SNS SNS_FIFO_TOPIC "$TOPIC" PASS LOW \
        "FIFO topic"
    else
        write_result "$REGION" SNS SNS_FIFO_TOPIC "$TOPIC" PASS LOW \
        "Standard topic"
    fi

###############################################################################
# TAGS
###############################################################################

    TAGS=$(aws sns list-tags-for-resource \
        --resource-arn "$TOPIC" \
        --query 'Tags[*].Key' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" SNS SNS_TAGS "$TOPIC" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" SNS SNS_TAGS "$TOPIC" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# OWNER
###############################################################################

    OWNER=$(aws sns get-topic-attributes \
        --topic-arn "$TOPIC" \
        --query 'Attributes.Owner' \
        --output text 2>/dev/null)

    if [[ -n "$OWNER" && "$OWNER" != "None" ]]
    then
        write_result "$REGION" SNS SNS_OWNER "$TOPIC" PASS LOW \
        "Owner information present"
    else
        write_result "$REGION" SNS SNS_OWNER "$TOPIC" FAIL LOW \
        "Owner information unavailable"
    fi

###############################################################################
# PUBLIC POLICY
###############################################################################

    POLICY=$(aws sns get-topic-attributes \
        --topic-arn "$TOPIC" \
        --query 'Attributes.Policy' \
        --output text 2>/dev/null)

    if echo "$POLICY" | grep -q '"Principal":"\*"'
    then
        write_result "$REGION" SNS SNS_POLICY_PUBLIC "$TOPIC" FAIL HIGH \
        "Public access policy detected"
    else
        write_result "$REGION" SNS SNS_POLICY_PUBLIC "$TOPIC" PASS HIGH \
        "No public access policy"
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
    SNS \
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
echo "SNS Audit Complete"
