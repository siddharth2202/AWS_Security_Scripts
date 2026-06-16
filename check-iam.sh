#!/bin/bash

set -uo pipefail

###############################################################################

# PRECHECKS

###############################################################################

if [[ ! -f "./common.sh" ]]
then
echo
echo "ERROR: common.sh not found"
echo
exit 1
fi

if [[ ! -f "./config.conf" ]]
then
echo
echo "ERROR: config.conf not found"
echo "Run ./bootstrap.sh first"
echo
exit 1
fi

source ./common.sh
source ./config.conf

###############################################################################

# VARIABLES

###############################################################################

SERVICE="IAM"

create_report_dir

REPORT_FILE="reports/iam-report.csv"
HTML_FILE="reports/iam-report.html"

init_csv "$REPORT_FILE"

echo
echo "Starting IAM Audit..."
echo

###############################################################################

# ROOT MFA

###############################################################################

ROOT_MFA=$(aws iam get-account-summary 
--query 'SummaryMap.AccountMFAEnabled' 
--output text 2>/dev/null)

if [[ "$ROOT_MFA" == "1" ]]
then

```
write_result \
    global \
    IAM \
    ROOT_MFA \
    Root \
    PASS \
    CRITICAL \
    "Root MFA enabled"
```

else

```
write_result \
    global \
    IAM \
    ROOT_MFA \
    Root \
    FAIL \
    CRITICAL \
    "Root MFA NOT enabled"
```

fi

###############################################################################

# ROOT ACCESS KEYS

###############################################################################

ROOT_KEYS=$(aws iam get-account-summary 
--query 'SummaryMap.AccountAccessKeysPresent' 
--output text 2>/dev/null)

if [[ "$ROOT_KEYS" == "0" ]]
then

```
write_result \
    global \
    IAM \
    ROOT_ACCESS_KEYS \
    Root \
    PASS \
    HIGH \
    "No root access keys"
```

else

```
write_result \
    global \
    IAM \
    ROOT_ACCESS_KEYS \
    Root \
    FAIL \
    HIGH \
    "Root access keys present"
```

fi

###############################################################################

# PASSWORD POLICY

###############################################################################

if aws iam get-account-password-policy >/dev/null 2>&1
then

```
write_result \
    global \
    IAM \
    PASSWORD_POLICY \
    Account \
    PASS \
    MEDIUM \
    "Password policy configured"
```

else

```
write_result \
    global \
    IAM \
    PASSWORD_POLICY \
    Account \
    FAIL \
    MEDIUM \
    "Password policy missing"
```

fi

###############################################################################

# IAM USERS

###############################################################################

USERS=$(aws iam list-users 
--query 'Users[*].UserName' 
--output text 2>/dev/null)

if [[ -z "$USERS" ]]
then

```
write_result \
    global \
    IAM \
    USER_DISCOVERY \
    N/A \
    INFO \
    INFO \
    "No IAM users found"
```

fi

###############################################################################

# USER MFA

###############################################################################

for USER in $USERS
do

```
MFA=$(aws iam list-mfa-devices \
    --user-name "$USER" \
    --query 'MFADevices[*].SerialNumber' \
    --output text 2>/dev/null)

if [[ -z "$MFA" ]]
then

    write_result \
        global \
        IAM \
        USER_MFA \
        "$USER" \
        FAIL \
        HIGH \
        "User without MFA"

else

    write_result \
        global \
        IAM \
        USER_MFA \
        "$USER" \
        PASS \
        LOW \
        "MFA enabled"

fi
```

done

###############################################################################

# ACCESS KEYS AGE

###############################################################################

for USER in $USERS
do

```
aws iam list-access-keys \
    --user-name "$USER" \
    --query 'AccessKeyMetadata[*].[AccessKeyId,CreateDate]' \
    --output text 2>/dev/null |

while read KEY CREATED
do

    [[ -z "$KEY" ]] && continue

    AGE=$(( ($(date +%s) - $(date -d "$CREATED" +%s)) / 86400 ))

    if (( AGE > 90 ))
    then

        write_result \
            global \
            IAM \
            OLD_ACCESS_KEY \
            "$KEY" \
            FAIL \
            HIGH \
            "Access key age=$AGE days"

    else

        write_result \
            global \
            IAM \
            OLD_ACCESS_KEY \
            "$KEY" \
            PASS \
            LOW \
            "Access key age=$AGE days"

    fi

done
```

done

###############################################################################

# ADMINISTRATOR ACCESS POLICY

###############################################################################

for USER in $USERS
do

```
POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$USER" \
    --query 'AttachedPolicies[*].PolicyName' \
    --output text 2>/dev/null)

if echo "$POLICIES" | grep -q "AdministratorAccess"
then

    write_result \
        global \
        IAM \
        ADMIN_ACCESS \
        "$USER" \
        FAIL \
        HIGH \
        "AdministratorAccess attached"

fi
```

done

###############################################################################

# HTML REPORT

###############################################################################

generate_html 
"$REPORT_FILE" 
"$HTML_FILE"

###############################################################################

# S3 UPLOAD

###############################################################################

if validate_bucket
then

```
upload_reports \
    IAM \
    "$REPORT_FILE" \
    "$HTML_FILE"
```

fi

###############################################################################

# COMPLETE

###############################################################################

echo
echo "CSV Report : $REPORT_FILE"
echo "HTML Report: $HTML_FILE"
echo
echo "IAM Audit Complete"
echo
