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

SERVICE="SQS"

create_report_dir

REPORT_FILE="reports/sqs-report.csv"
HTML_FILE="reports/sqs-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# QUEUES
###############################################################################

QUEUES=$(aws sqs list-queues \
    --query 'QueueUrls[*]' \
    --output text 2>/dev/null)

for QUEUE in $QUEUES
do

    REGION="$DEFAULT_REGION"

###############################################################################
# ENCRYPTION
###############################################################################

    SSE=$(aws sqs get-queue-attributes \
        --queue-url "$QUEUE" \
        --attribute-names KmsMasterKeyId SqsManagedSseEnabled \
        --query 'Attributes' \
        --output text 2>/dev/null)

    if [[ -n "$SSE" ]]
    then
        write_result "$REGION" SQS SQS_ENCRYPTION "$QUEUE" PASS HIGH \
        "Encryption enabled"
    else
        write_result "$REGION" SQS SQS_ENCRYPTION "$QUEUE" FAIL HIGH \
        "Encryption disabled"
    fi

###############################################################################
# QUEUE POLICY
###############################################################################

    POLICY=$(aws sqs get-queue-attributes \
        --queue-url "$QUEUE" \
        --attribute-names Policy \
        --query 'Attributes.Policy' \
        --output text 2>/dev/null)

    if [[ -n "$POLICY" && "$POLICY" != "None" ]]
    then
        write_result "$REGION" SQS SQS_POLICY "$QUEUE" PASS MEDIUM \
        "Queue policy configured"
    else
        write_result "$REGION" SQS SQS_POLICY "$QUEUE" FAIL MEDIUM \
        "Queue policy missing"
    fi

###############################################################################
# PUBLIC POLICY
###############################################################################

    if echo "$POLICY" | grep -q '"Principal":"\*"'
    then
        write_result "$REGION" SQS SQS_PUBLIC_POLICY "$QUEUE" FAIL HIGH \
        "Public access policy detected"
    else
        write_result "$REGION" SQS SQS_PUBLIC_POLICY "$QUEUE" PASS HIGH \
        "No public access policy"
    fi

###############################################################################
# DEAD LETTER QUEUE
###############################################################################

    REDRIVE=$(aws sqs get-queue-attributes \
        --queue-url "$QUEUE" \
        --attribute-names RedrivePolicy \
        --query 'Attributes.RedrivePolicy' \
        --output text 2>/dev/null)

    if [[ -n "$REDRIVE" && "$REDRIVE" != "None" ]]
    then
        write_result "$REGION" SQS DLQ_CONFIGURED "$QUEUE" PASS LOW \
        "Dead-letter queue configured"
    else
        write_result "$REGION" SQS DLQ_CONFIGURED "$QUEUE" FAIL LOW \
        "Dead-letter queue missing"
    fi

###############################################################################
# MESSAGE RETENTION
###############################################################################

    RETENTION=$(aws sqs get-queue-attributes \
        --queue-url "$QUEUE" \
        --attribute-names MessageRetentionPeriod \
        --query 'Attributes.MessageRetentionPeriod' \
        --output text 2>/dev/null)

    if [[ "$RETENTION" -gt 0 ]]
    then
        write_result "$REGION" SQS MESSAGE_RETENTION "$QUEUE" PASS LOW \
        "Retention period: $RETENTION seconds"
    else
        write_result "$REGION" SQS MESSAGE_RETENTION "$QUEUE" FAIL LOW \
        "Retention period not configured"
    fi

###############################################################################
# VISIBILITY TIMEOUT
###############################################################################

    VISIBILITY=$(aws sqs get-queue-attributes \
        --queue-url "$QUEUE" \
        --attribute-names VisibilityTimeout \
        --query 'Attributes.VisibilityTimeout' \
        --output text 2>/dev/null)

    if [[ "$VISIBILITY" -gt 0 ]]
    then
        write_result "$REGION" SQS VISIBILITY_TIMEOUT "$QUEUE" PASS LOW \
        "Visibility timeout: $VISIBILITY seconds"
    else
        write_result "$REGION" SQS VISIBILITY_TIMEOUT "$QUEUE" FAIL LOW \
        "Visibility timeout not configured"
    fi

###############################################################################
# DELIVERY DELAY
###############################################################################

    DELAY=$(aws sqs get-queue-attributes \
        --queue-url "$QUEUE" \
        --attribute-names DelaySeconds \
        --query 'Attributes.DelaySeconds' \
        --output text 2>/dev/null)

    if [[ "$DELAY" -gt 0 ]]
    then
        write_result "$REGION" SQS DELAY_QUEUE "$QUEUE" PASS LOW \
        "Delivery delay configured"
    else
        write_result "$REGION" SQS DELAY_QUEUE "$QUEUE" PASS LOW \
        "No delivery delay"
    fi

###############################################################################
# FIFO QUEUE
###############################################################################

    FIFO=$(aws sqs get-queue-attributes \
        --queue-url "$QUEUE" \
        --attribute-names FifoQueue \
        --query 'Attributes.FifoQueue' \
        --output text 2>/dev/null)

    if [[ "$FIFO" == "true" ]]
    then
        write_result "$REGION" SQS FIFO_QUEUE "$QUEUE" PASS LOW \
        "FIFO queue"
    else
        write_result "$REGION" SQS FIFO_QUEUE "$QUEUE" PASS LOW \
        "Standard queue"
    fi

###############################################################################
# TAGS
###############################################################################

    TAGS=$(aws sqs list-queue-tags \
        --queue-url "$QUEUE" \
        --query 'Tags' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" SQS TAGS_PRESENT "$QUEUE" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" SQS TAGS_PRESENT "$QUEUE" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# CUSTOMER KMS KEY
###############################################################################

    KMS_KEY=$(aws sqs get-queue-attributes \
        --queue-url "$QUEUE" \
        --attribute-names KmsMasterKeyId \
        --query 'Attributes.KmsMasterKeyId' \
        --output text 2>/dev/null)

    if [[ -n "$KMS_KEY" && "$KMS_KEY" != "None" ]]
    then
        write_result "$REGION" SQS KMS_KEY "$QUEUE" PASS HIGH \
        "Customer-managed KMS key configured"
    else
        write_result "$REGION" SQS KMS_KEY "$QUEUE" FAIL HIGH \
        "Customer-managed KMS key not configured"
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
    SQS \
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
echo "SQS Audit Complete"
