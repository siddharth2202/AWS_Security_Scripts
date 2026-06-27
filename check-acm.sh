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

SERVICE="ACM"

create_report_dir

REPORT_FILE="reports/acm-report.csv"
HTML_FILE="reports/acm-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# CERTIFICATES
###############################################################################

CERTIFICATES=$(aws acm list-certificates \
    --query 'CertificateSummaryList[*].CertificateArn' \
    --output text 2>/dev/null)

for CERT in $CERTIFICATES
do

    REGION="$DEFAULT_REGION"

###############################################################################
# CERTIFICATE STATUS
###############################################################################

    STATUS=$(aws acm describe-certificate \
        --certificate-arn "$CERT" \
        --query 'Certificate.Status' \
        --output text 2>/dev/null)

    if [[ "$STATUS" == "ISSUED" ]]
    then
        write_result "$REGION" ACM CERTIFICATE_VALID "$CERT" PASS CRITICAL \
        "Certificate issued"
    else
        write_result "$REGION" ACM CERTIFICATE_VALID "$CERT" FAIL CRITICAL \
        "Certificate status: $STATUS"
    fi

###############################################################################
# CERTIFICATE IN USE
###############################################################################

    IN_USE=$(aws acm describe-certificate \
        --certificate-arn "$CERT" \
        --query 'Certificate.InUseBy' \
        --output text 2>/dev/null)

    if [[ -n "$IN_USE" && "$IN_USE" != "None" ]]
    then
        write_result "$REGION" ACM CERTIFICATE_IN_USE "$CERT" PASS HIGH \
        "Certificate attached to AWS resource"
    else
        write_result "$REGION" ACM CERTIFICATE_IN_USE "$CERT" FAIL HIGH \
        "Certificate not in use"
    fi

###############################################################################
# EXPIRY
###############################################################################

    EXPIRY=$(aws acm describe-certificate \
        --certificate-arn "$CERT" \
        --query 'Certificate.NotAfter' \
        --output text 2>/dev/null)

    if [[ -n "$EXPIRY" && "$EXPIRY" != "None" ]]
    then
        write_result "$REGION" ACM EXPIRY_CHECK "$CERT" PASS HIGH \
        "Expires: $EXPIRY"
    else
        write_result "$REGION" ACM EXPIRY_CHECK "$CERT" FAIL HIGH \
        "Expiry unavailable"
    fi

###############################################################################
# AUTO RENEWAL
###############################################################################

    RENEWAL=$(aws acm describe-certificate \
        --certificate-arn "$CERT" \
        --query 'Certificate.RenewalEligibility' \
        --output text 2>/dev/null)

    if [[ "$RENEWAL" == "ELIGIBLE" ]]
    then
        write_result "$REGION" ACM AUTO_RENEWAL "$CERT" PASS HIGH \
        "Automatic renewal eligible"
    else
        write_result "$REGION" ACM AUTO_RENEWAL "$CERT" FAIL HIGH \
        "Automatic renewal not eligible"
    fi

###############################################################################
# KEY ALGORITHM
###############################################################################

    KEY=$(aws acm describe-certificate \
        --certificate-arn "$CERT" \
        --query 'Certificate.KeyAlgorithm' \
        --output text 2>/dev/null)

    if [[ -n "$KEY" && "$KEY" != "None" ]]
    then
        write_result "$REGION" ACM KEY_ALGORITHM "$CERT" PASS MEDIUM \
        "$KEY"
    else
        write_result "$REGION" ACM KEY_ALGORITHM "$CERT" FAIL MEDIUM \
        "Key algorithm unavailable"
    fi

###############################################################################
# SIGNATURE ALGORITHM
###############################################################################

    SIGNATURE=$(aws acm describe-certificate \
        --certificate-arn "$CERT" \
        --query 'Certificate.SignatureAlgorithm' \
        --output text 2>/dev/null)

    if [[ -n "$SIGNATURE" && "$SIGNATURE" != "None" ]]
    then
        write_result "$REGION" ACM SIGNATURE_ALGORITHM "$CERT" PASS MEDIUM \
        "$SIGNATURE"
    else
        write_result "$REGION" ACM SIGNATURE_ALGORITHM "$CERT" FAIL MEDIUM \
        "Signature algorithm unavailable"
    fi

###############################################################################
# CERTIFICATE TYPE
###############################################################################

    TYPE=$(aws acm describe-certificate \
        --certificate-arn "$CERT" \
        --query 'Certificate.Type' \
        --output text 2>/dev/null)

    if [[ -n "$TYPE" && "$TYPE" != "None" ]]
    then
        write_result "$REGION" ACM CERTIFICATE_TYPE "$CERT" PASS LOW \
        "$TYPE"
    else
        write_result "$REGION" ACM CERTIFICATE_TYPE "$CERT" FAIL LOW \
        "Certificate type unavailable"
    fi

###############################################################################
# CERTIFICATE TAGS
###############################################################################

    TAGS=$(aws acm list-tags-for-certificate \
        --certificate-arn "$CERT" \
        --query 'Tags[*].Key' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "None" ]]
    then
        write_result "$REGION" ACM CERTIFICATE_TAGS "$CERT" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" ACM CERTIFICATE_TAGS "$CERT" FAIL LOW \
        "No tags configured"
    fi

###############################################################################
# DOMAIN VALIDATION
###############################################################################

    VALIDATION=$(aws acm describe-certificate \
        --certificate-arn "$CERT" \
        --query 'Certificate.DomainValidationOptions[0].ValidationStatus' \
        --output text 2>/dev/null)

    if [[ "$VALIDATION" == "SUCCESS" ]]
    then
        write_result "$REGION" ACM DOMAIN_VALIDATION "$CERT" PASS LOW \
        "Domain validation successful"
    else
        write_result "$REGION" ACM DOMAIN_VALIDATION "$CERT" FAIL LOW \
        "Validation status: $VALIDATION"
    fi

###############################################################################
# CERTIFICATE STATUS
###############################################################################

    STATUS=$(aws acm describe-certificate \
        --certificate-arn "$CERT" \
        --query 'Certificate.Status' \
        --output text 2>/dev/null)

    if [[ "$STATUS" == "ISSUED" ]]
    then
        write_result "$REGION" ACM CERTIFICATE_STATUS "$CERT" PASS LOW \
        "Certificate active"
    else
        write_result "$REGION" ACM CERTIFICATE_STATUS "$CERT" FAIL LOW \
        "Status: $STATUS"
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
    ACM \
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
echo "ACM Audit Complete"
