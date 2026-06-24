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

SERVICE="CONFIG"

create_report_dir

REPORT_FILE="reports/config-report.csv"
HTML_FILE="reports/config-report.html"

init_csv "$REPORT_FILE"

REGION="$DEFAULT_REGION"

###############################################################################
# CONFIG RECORDER
###############################################################################

RECORDER=$(aws configservice describe-configuration-recorders \
    --query 'ConfigurationRecorders[*].name' \
    --output text 2>/dev/null)

if [[ -n "$RECORDER" ]]
then
    write_result "$REGION" CONFIG CONFIG_RECORDER Account PASS HIGH \
    "Configuration recorder configured"
else
    write_result "$REGION" CONFIG CONFIG_RECORDER Account FAIL HIGH \
    "No configuration recorder found"
fi

###############################################################################
# DELIVERY CHANNEL
###############################################################################

CHANNEL=$(aws configservice describe-delivery-channels \
    --query 'DeliveryChannels[*].name' \
    --output text 2>/dev/null)

if [[ -n "$CHANNEL" ]]
then
    write_result "$REGION" CONFIG DELIVERY_CHANNEL Account PASS HIGH \
    "Delivery channel configured"
else
    write_result "$REGION" CONFIG DELIVERY_CHANNEL Account FAIL HIGH \
    "Delivery channel missing"
fi

###############################################################################
# CONFIG SERVICE ENABLED
###############################################################################

STATUS=$(aws configservice describe-configuration-recorder-status \
    --query 'ConfigurationRecordersStatus[0].recording' \
    --output text 2>/dev/null)

if [[ "$STATUS" == "True" ]]
then
    write_result "$REGION" CONFIG CONFIG_SERVICE Account PASS HIGH \
    "Configuration recording enabled"
else
    write_result "$REGION" CONFIG CONFIG_SERVICE Account FAIL HIGH \
    "Configuration recording disabled"
fi

###############################################################################
# ALL RESOURCE TYPES
###############################################################################

ALL_TYPES=$(aws configservice describe-configuration-recorders \
    --query 'ConfigurationRecorders[0].recordingGroup.allSupported' \
    --output text 2>/dev/null)

if [[ "$ALL_TYPES" == "True" ]]
then
    write_result "$REGION" CONFIG ALL_RESOURCE_TYPES Account PASS MEDIUM \
    "Recording all supported resource types"
else
    write_result "$REGION" CONFIG ALL_RESOURCE_TYPES Account FAIL MEDIUM \
    "Not recording all resource types"
fi

###############################################################################
# GLOBAL RESOURCE TYPES
###############################################################################

GLOBAL=$(aws configservice describe-configuration-recorders \
    --query 'ConfigurationRecorders[0].recordingGroup.includeGlobalResourceTypes' \
    --output text 2>/dev/null)

if [[ "$GLOBAL" == "True" ]]
then
    write_result "$REGION" CONFIG GLOBAL_RESOURCES Account PASS LOW \
    "Global resources recorded"
else
    write_result "$REGION" CONFIG GLOBAL_RESOURCES Account FAIL LOW \
    "Global resources not recorded"
fi

###############################################################################
# CONFIG RULES
###############################################################################

RULES=$(aws configservice describe-config-rules \
    --query 'ConfigRules[*].ConfigRuleName' \
    --output text 2>/dev/null)

if [[ -n "$RULES" ]]
then
    write_result "$REGION" CONFIG CONFIG_RULES Account PASS MEDIUM \
    "Config rules configured"
else
    write_result "$REGION" CONFIG CONFIG_RULES Account FAIL MEDIUM \
    "No Config rules found"
fi

###############################################################################
# COMPLIANCE RESULTS
###############################################################################

COMPLIANCE=$(aws configservice describe-compliance-by-config-rule \
    --query 'ComplianceByConfigRules[*].Compliance.Type' \
    --output text 2>/dev/null)

if [[ -n "$COMPLIANCE" ]]
then
    write_result "$REGION" CONFIG COMPLIANCE_RESULTS Account PASS MEDIUM \
    "Compliance evaluations available"
else
    write_result "$REGION" CONFIG COMPLIANCE_RESULTS Account FAIL MEDIUM \
    "No compliance evaluations found"
fi

###############################################################################
# CONFIG AGGREGATORS
###############################################################################

AGGREGATOR=$(aws configservice describe-configuration-aggregators \
    --query 'ConfigurationAggregators[*].ConfigurationAggregatorName' \
    --output text 2>/dev/null)

if [[ -n "$AGGREGATOR" ]]
then
    write_result "$REGION" CONFIG AGGREGATOR Account PASS LOW \
    "Configuration aggregator configured"
else
    write_result "$REGION" CONFIG AGGREGATOR Account FAIL LOW \
    "No configuration aggregator found"
fi

###############################################################################
# CONFORMANCE PACKS
###############################################################################

PACKS=$(aws configservice describe-conformance-packs \
    --query 'ConformancePackDetails[*].ConformancePackName' \
    --output text 2>/dev/null)

if [[ -n "$PACKS" ]]
then
    write_result "$REGION" CONFIG CONFORMANCE_PACKS Account PASS LOW \
    "Conformance packs configured"
else
    write_result "$REGION" CONFIG CONFORMANCE_PACKS Account FAIL LOW \
    "No conformance packs found"
fi

###############################################################################
# AUTO REMEDIATION
###############################################################################

REMEDIATION=$(aws configservice describe-remediation-configurations \
    --query 'RemediationConfigurations[*].ConfigRuleName' \
    --output text 2>/dev/null)

if [[ -n "$REMEDIATION" ]]
then
    write_result "$REGION" CONFIG AUTO_REMEDIATION Account PASS LOW \
    "Automatic remediation configured"
else
    write_result "$REGION" CONFIG AUTO_REMEDIATION Account FAIL LOW \
    "Automatic remediation not configured"
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
    CONFIG \
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
echo "AWS Config Audit Complete"
