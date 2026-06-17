#!/bin/bash

set -uo pipefail

export TZ=Asia/Kolkata
DATE=$(date '+%Y-%m-%d %H:%M:%S IST')
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

    echo "\"$DATE\",\"$ACCOUNT_ID\",\"$REGION\",\"$SERVICE\",\"$CHECK\",\"$RESOURCE\",\"$STATUS\",\"$SEVERITY\",\"$DETAILS\"" \
    >> "$REPORT_FILE"

}

###############################################################################
# HTML REPORT
###############################################################################

generate_html() {

    local CSV="$1"
    local HTML="$2"

    {
        PASS_COUNT=$(awk -F',' '$7 ~ /PASS/ {count++} END {print count+0}' "$CSV")
        FAIL_COUNT=$(awk -F',' '$7 ~ /FAIL/ {count++} END {print count+0}' "$CSV")
        TOTAL=$((PASS_COUNT + FAIL_COUNT))

        echo "<html>"
        echo "<head>"
        echo "<title>AWS Security Assessment Report</title>"

        echo "<style>"
        echo "body{font-family:'Segoe UI',Arial,sans-serif;background:#f4f6f9;margin:0;padding:0;color:#333}"
        echo ".header{background:#232F3E;color:white;padding:25px;text-align:center}"
        echo ".header h1{margin:0;font-size:30px}"
        echo ".container{padding:20px}"
        echo ".cards{display:flex;gap:20px;margin-bottom:20px;flex-wrap:wrap}"
        echo ".card{background:white;padding:15px;border-radius:10px;box-shadow:0 2px 8px rgba(0,0,0,0.1);min-width:220px}"
        echo ".card-title{font-size:12px;color:#666;text-transform:uppercase}"
        echo ".card-value{font-size:20px;font-weight:bold;color:#232F3E}"
        echo "table{border-collapse:collapse;width:100%;background:white;box-shadow:0 2px 8px rgba(0,0,0,0.1)}"
        echo "th{background:#232F3E;color:white;padding:12px}"
        echo "td{padding:10px;border-bottom:1px solid #ddd}"
        echo "tr:nth-child(even){background:#f8f9fb}"
        echo "tr:hover{background:#eef5ff}"
        echo ".PASS{background:#d4edda !important}"
        echo ".FAIL{background:#f8d7da !important}"
        echo "</style>"

        echo "</head>"
        echo "<body>"

        echo "<div class='header'>"
        echo "<h1>AWS Security Assessment Report</h1>"
        echo "</div>"

        echo "<div class='container'>"

        echo "<div class='cards'>"

        echo "<div class='card'>"
        echo "<div class='card-title'>AWS Account</div>"
        echo "<div class='card-value'>$ACCOUNT_ID</div>"
        echo "</div>"

        echo "<div class='card'>"
        echo "<div class='card-title'>Generated</div>"
        echo "<div class='card-value'>$DATE</div>"
        echo "</div>"

        echo "</div>"

        echo "<div class='cards'>"

        echo "<div class='card'>"
        echo "<div class='card-title'>Total Checks</div>"
        echo "<div class='card-value'>$TOTAL</div>"
        echo "</div>"

        echo "<div class='card'>"
        echo "<div class='card-title'>Passed</div>"
        echo "<div class='card-value'>$PASS_COUNT</div>"
        echo "</div>"

        echo "<div class='card'>"
        echo "<div class='card-title'>Failed</div>"
        echo "<div class='card-value'>$FAIL_COUNT</div>"
        echo "</div>"

        echo "</div>"

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
        echo "</div>"
        echo "</body>"
        echo "</html>"

    } > "$HTML"

}


##############################################################################
# REPORT BUCKET VALIDATION
###############################################################################

validate_bucket() {

    [[ "${AUTO_UPLOAD:-false}" != "true" ]] && return 0

    aws s3api head-bucket \
        --bucket "$REPORT_BUCKET" \
        >/dev/null 2>&1

    if [[ $? -eq 0 ]]
    then
        return 0
    fi

    echo
    echo "Report bucket missing."
    echo "Running bootstrap.sh..."
    echo

    chmod +x bootstrap.sh
    ./bootstrap.sh >/dev/null 2>&1

    aws s3api head-bucket \
        --bucket "$REPORT_BUCKET" \
        >/dev/null 2>&1

    if [[ $? -eq 0 ]]
    then

        echo
        echo "Report bucket recreated successfully"
        echo

        return 0

    fi

    echo
    echo "ERROR: Unable to create report bucket"
    echo
    return 1
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
