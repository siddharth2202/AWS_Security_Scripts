#!/bin/bash

set -uo pipefail

DATE=$(date '+%Y-%m-%d %H:%M:%S')
DATE_FOLDER=$(date '+%Y-%m-%d')

ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account \
    --output text 2>/dev/null)

create_report_dir() {
    mkdir -p reports
}

###############################################################################
# CSV
###############################################################################

init_csv() {

    REPORT_FILE="$1"

    echo "Timestamp,AccountId,Region,Service,Check,Resource,Status,Severity,Details" \
    > "$REPORT_FILE"

}

write_result() {

    local REGION="$1"
    local SERVICE="$2"
    local CHECK="$3"
    local RESOURCE="$4"
    local STATUS="$5"
    local SEVERITY="$6"
    local DETAILS="$7"

    echo "\"$DATE\",\"=\"$ACCOUNT_ID\"\",\"$REGION\",\"$SERVICE\",\"$CHECK\",\"$RESOURCE\",\"$STATUS\",\"$SEVERITY\",\"$DETAILS\"" \
    >> "$REPORT_FILE"

}

###############################################################################
# HTML REPORT
###############################################################################

generate_html() {

    local CSV="$1"
    local HTML="$2"

    {
        echo "<html>"
        echo "<head>"
        echo "<style>"
        echo "body{font-family:Arial,sans-serif;margin:20px}"
        echo "h2{color:#232f3e}"
        echo "table{border-collapse:collapse;width:100%}"
        echo "th{background:#232f3e;color:white}"
        echo "th,td{border:1px solid #ddd;padding:8px;text-align:left}"
        echo ".PASS{background:#d4edda}"
        echo ".FAIL{background:#f8d7da}"
        echo ".WARN{background:#fff3cd}"
        echo "</style>"
        echo "</head>"
        echo "<body>"

        echo "<h2>AWS Security Audit Report</h2>"
        echo "<p><b>Account:</b> $ACCOUNT_ID</p>"
        echo "<p><b>Generated:</b> $DATE</p>"

        echo "<table>"

        FIRST=1

        while IFS=',' read -r c1 c2 c3 c4 c5 c6 c7 c8 c9
        do

            if [[ $FIRST -eq 1 ]]
            then

                echo "<tr>"
                echo "<th>$c1</th>"
                echo "<th>$c2</th>"
                echo "<th>$c3</th>"
                echo "<th>$c4</th>"
                echo "<th>$c5</th>"
                echo "<th>$c6</th>"
                echo "<th>$c7</th>"
                echo "<th>$c8</th>"
                echo "<th>$c9</th>"
                echo "</tr>"

                FIRST=0
                continue

            fi

            CLASS=""

            [[ "$c7" == *PASS* ]] && CLASS="PASS"
            [[ "$c7" == *FAIL* ]] && CLASS="FAIL"

            echo "<tr class='$CLASS'>"
            echo "<td>$c1</td>"
            echo "<td>$c2</td>"
            echo "<td>$c3</td>"
            echo "<td>$c4</td>"
            echo "<td>$c5</td>"
            echo "<td>$c6</td>"
            echo "<td>$c7</td>"
            echo "<td>$c8</td>"
            echo "<td>$c9</td>"
            echo "</tr>"

        done < "$CSV"

        echo "</table>"
        echo "</body>"
        echo "</html>"

    } > "$HTML"

}

###############################################################################
# REPORT BUCKET VALIDATION
###############################################################################

validate_bucket() {

    [[ "${AUTO_UPLOAD:-false}" != "true" ]] && return 0

    aws s3api head-bucket \
        --bucket "$REPORT_BUCKET" \
        >/dev/null 2>&1

    if [[ $? -ne 0 ]]
    then

        echo
        echo "ERROR: Report bucket does not exist:"
        echo "$REPORT_BUCKET"
        echo
        return 1

    fi

    return 0
}

###############################################################################
# REPORT UPLOAD
###############################################################################

upload_reports() {

    [[ "${AUTO_UPLOAD:-false}" != "true" ]] && return 0

    local SERVICE="$1"
    local CSV_FILE="$2"
    local HTML_FILE="$3"

    PREFIX="$ACCOUNT_ID/$DATE_FOLDER/$SERVICE"

    aws s3 cp "$CSV_FILE" \
        "s3://$REPORT_BUCKET/$PREFIX/" \
        >/dev/null

    CSV_STATUS=$?

    aws s3 cp "$HTML_FILE" \
        "s3://$REPORT_BUCKET/$PREFIX/" \
        >/dev/null

    HTML_STATUS=$?

    if [[ $CSV_STATUS -eq 0 && $HTML_STATUS -eq 0 ]]
    then

        echo
        echo "Reports Uploaded Successfully"
        echo

        echo "CSV:"
        echo "s3://$REPORT_BUCKET/$PREFIX/$(basename "$CSV_FILE")"
        echo

        echo "HTML:"
        echo "s3://$REPORT_BUCKET/$PREFIX/$(basename "$HTML_FILE")"
        echo

    else

        echo
        echo "ERROR: Report upload failed"
        echo

        return 1

    fi

}

###############################################################################
# REGIONS
###############################################################################

get_regions() {

    aws ec2 describe-regions \
        --query 'Regions[*].RegionName' \
        --output text 2>/dev/null

}
