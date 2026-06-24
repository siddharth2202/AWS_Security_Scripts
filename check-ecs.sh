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

SERVICE="ECS"

create_report_dir

REPORT_FILE="reports/ecs-report.csv"
HTML_FILE="reports/ecs-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# ECS CLUSTERS
###############################################################################

ECS_CLUSTERS=$(aws ecs list-clusters \
    --query 'clusterArns[*]' \
    --output text 2>/dev/null)

for ECS_CLUSTER in $ECS_CLUSTERS
do

    REGION="$DEFAULT_REGION"

###############################################################################
# CONTAINER INSIGHTS
###############################################################################

    INSIGHTS=$(aws ecs describe-clusters \
        --clusters "$ECS_CLUSTER" \
        --include SETTINGS \
        --query 'clusters[0].settings[?name==`containerInsights`].value' \
        --output text 2>/dev/null)

    if [[ "$INSIGHTS" == "enabled" ]]
    then
        write_result "$REGION" ECS ECS_CONTAINER_INSIGHTS "$ECS_CLUSTER" PASS LOW \
        "Container Insights enabled"
    else
        write_result "$REGION" ECS ECS_CONTAINER_INSIGHTS "$ECS_CLUSTER" FAIL LOW \
        "Container Insights disabled"
    fi

###############################################################################
# ECS EXEC
###############################################################################

    EXEC_LOGGING=$(aws ecs describe-clusters \
        --clusters "$ECS_CLUSTER" \
        --query 'clusters[0].configuration.executeCommandConfiguration.logging' \
        --output text 2>/dev/null)

    if [[ -n "$EXEC_LOGGING" && "$EXEC_LOGGING" != "None" ]]
    then
        write_result "$REGION" ECS ECS_EXEC_ENABLED "$ECS_CLUSTER" PASS MEDIUM \
        "Execute command configured"
    else
        write_result "$REGION" ECS ECS_EXEC_ENABLED "$ECS_CLUSTER" FAIL MEDIUM \
        "Execute command not configured"
    fi

###############################################################################
# ECS TASK ROLE
###############################################################################

    SERVICE_ARNS=$(aws ecs list-services \
        --cluster "$ECS_CLUSTER" \
        --query 'serviceArns[*]' \
        --output text 2>/dev/null)

    if [[ -n "$SERVICE_ARNS" && "$SERVICE_ARNS" != "None" ]]
    then
        write_result "$REGION" ECS ECS_TASK_ROLE "$ECS_CLUSTER" PASS HIGH \
        "Services present"
    else
        write_result "$REGION" ECS ECS_TASK_ROLE "$ECS_CLUSTER" FAIL HIGH \
        "No services present"
    fi

###############################################################################
# ECS FARGATE
###############################################################################

    CAPACITY_PROVIDERS=$(aws ecs describe-clusters \
        --clusters "$ECS_CLUSTER" \
        --query 'clusters[0].capacityProviders' \
        --output text 2>/dev/null)

    if echo "$CAPACITY_PROVIDERS" | grep -q "FARGATE"
    then
        write_result "$REGION" ECS ECS_FARGATE "$ECS_CLUSTER" PASS LOW \
        "Fargate enabled"
    else
        write_result "$REGION" ECS ECS_FARGATE "$ECS_CLUSTER" PASS LOW \
        "EC2 launch type"
    fi

###############################################################################
# TAGS
###############################################################################

    TAG_KEYS=$(aws ecs list-tags-for-resource \
        --resource-arn "$ECS_CLUSTER" \
        --query 'tags[*].key' \
        --output text 2>/dev/null)

    if [[ -n "$TAG_KEYS" ]]
    then
        write_result "$REGION" ECS ECS_TAGS "$ECS_CLUSTER" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" ECS ECS_TAGS "$ECS_CLUSTER" FAIL LOW \
        "No tags configured"
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
    ECS \
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
echo "ECS Audit Complete"
