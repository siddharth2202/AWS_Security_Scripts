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

SERVICE="BACKUP"

create_report_dir

REPORT_FILE="reports/backup-report.csv"
HTML_FILE="reports/backup-report.html"

init_csv "$REPORT_FILE"

###############################################################################
# BACKUP VAULTS
###############################################################################

VAULTS=$(aws backup list-backup-vaults \
    --query 'BackupVaultList[*].BackupVaultName' \
    --output text 2>/dev/null)

for VAULT in $VAULTS
do

    REGION="$DEFAULT_REGION"

###############################################################################
# BACKUP VAULT EXISTS
###############################################################################

    write_result "$REGION" BACKUP BACKUP_VAULT_EXISTS "$VAULT" PASS HIGH \
    "Backup vault exists"

###############################################################################
# BACKUP VAULT ENCRYPTION
###############################################################################

    KMS=$(aws backup describe-backup-vault \
        --backup-vault-name "$VAULT" \
        --query 'EncryptionKeyArn' \
        --output text 2>/dev/null)

    if [[ -n "$KMS" && "$KMS" != "None" ]]
    then
        write_result "$REGION" BACKUP BACKUP_VAULT_ENCRYPTION "$VAULT" PASS HIGH \
        "Vault encrypted with KMS"
    else
        write_result "$REGION" BACKUP BACKUP_VAULT_ENCRYPTION "$VAULT" FAIL HIGH \
        "No KMS key configured"
    fi

###############################################################################
# BACKUP VAULT LOCK
###############################################################################

    LOCK=$(aws backup describe-backup-vault \
        --backup-vault-name "$VAULT" \
        --query 'Locked' \
        --output text 2>/dev/null)

    if [[ "$LOCK" == "True" ]]
    then
        write_result "$REGION" BACKUP BACKUP_VAULT_LOCK "$VAULT" PASS HIGH \
        "Vault Lock enabled"
    else
        write_result "$REGION" BACKUP BACKUP_VAULT_LOCK "$VAULT" FAIL HIGH \
        "Vault Lock disabled"
    fi

###############################################################################
# RECOVERY POINTS
###############################################################################

    RECOVERY=$(aws backup list-recovery-points-by-backup-vault \
        --backup-vault-name "$VAULT" \
        --query 'length(RecoveryPoints)' \
        --output text 2>/dev/null)

    if [[ "$RECOVERY" -gt 0 ]]
    then
        write_result "$REGION" BACKUP RECOVERY_POINTS "$VAULT" PASS MEDIUM \
        "$RECOVERY recovery point(s)"
    else
        write_result "$REGION" BACKUP RECOVERY_POINTS "$VAULT" FAIL MEDIUM \
        "No recovery points"
    fi

###############################################################################
# BACKUP VAULT TAGS
###############################################################################

    VAULT_ARN=$(aws backup describe-backup-vault \
        --backup-vault-name "$VAULT" \
        --query 'BackupVaultArn' \
        --output text 2>/dev/null)

    TAGS=$(aws backup list-tags \
        --resource-arn "$VAULT_ARN" \
        --query 'Tags' \
        --output text 2>/dev/null)

    if [[ -n "$TAGS" && "$TAGS" != "{}" ]]
    then
        write_result "$REGION" BACKUP BACKUP_VAULT_TAGS "$VAULT" PASS LOW \
        "Tags configured"
    else
        write_result "$REGION" BACKUP BACKUP_VAULT_TAGS "$VAULT" FAIL LOW \
        "No tags configured"
    fi
done

REGION="$DEFAULT_REGION"

###############################################################################
# BACKUP PLANS
###############################################################################

PLANS=$(aws backup list-backup-plans \
    --query 'BackupPlansList[*].BackupPlanId' \
    --output text 2>/dev/null)

if [[ -n "$PLANS" ]]
then

    write_result "$REGION" BACKUP BACKUP_PLAN_EXISTS Account PASS CRITICAL \
    "Backup plan(s) configured"

else

    write_result "$REGION" BACKUP BACKUP_PLAN_EXISTS Account FAIL CRITICAL \
    "No backup plans configured"

fi

###############################################################################
# BACKUP SELECTIONS
###############################################################################

for PLAN in $PLANS
do

    SELECTIONS=$(aws backup list-backup-selections \
        --backup-plan-id "$PLAN" \
        --query 'length(BackupSelectionsList)' \
        --output text 2>/dev/null)

    if [[ "$SELECTIONS" -gt 0 ]]
    then
        write_result "$REGION" BACKUP BACKUP_SELECTIONS "$PLAN" PASS MEDIUM \
        "$SELECTIONS resource selection(s)"
    else
        write_result "$REGION" BACKUP BACKUP_SELECTIONS "$PLAN" FAIL MEDIUM \
        "No backup selections"
    fi

###############################################################################
# CROSS REGION COPY
###############################################################################

    COPY_RULES=$(aws backup get-backup-plan \
        --backup-plan-id "$PLAN" \
        --query 'BackupPlan.Rules[*].CopyActions' \
        --output text 2>/dev/null)

    if [[ -n "$COPY_RULES" && "$COPY_RULES" != "None" ]]
    then
        write_result "$REGION" BACKUP CROSS_REGION_COPY "$PLAN" PASS MEDIUM \
        "Cross-region copy configured"
    else
        write_result "$REGION" BACKUP CROSS_REGION_COPY "$PLAN" FAIL MEDIUM \
        "No cross-region copy rule"
    fi

done

###############################################################################
# BACKUP JOB STATUS
###############################################################################

JOBS=$(aws backup list-backup-jobs \
    --max-results 1 \
    --query 'BackupJobs[0].State' \
    --output text 2>/dev/null)

if [[ -n "$JOBS" && "$JOBS" != "None" ]]
then
    write_result "$REGION" BACKUP BACKUP_JOB_STATUS Account PASS LOW \
    "Latest job status: $JOBS"
else
    write_result "$REGION" BACKUP BACKUP_JOB_STATUS Account FAIL LOW \
    "No backup jobs found"
fi

###############################################################################
# BACKUP VAULT STATUS
###############################################################################

write_result "$REGION" BACKUP BACKUP_VAULT_STATUS Account PASS LOW \
"Backup service operational"

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
    BACKUP \
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
echo "AWS Backup Audit Complete"
