#!/usr/bin/env bash
set -euo pipefail

: "${STATE_BUCKET:?STATE_BUCKET is required}"
: "${PLAN_EXIT_CODE:?PLAN_EXIT_CODE is required}"
: "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL is required}"

STATUS_KEY="todoapp/github-actions/drift-status.txt"

case "$PLAN_EXIT_CODE" in
  0) CURRENT_STATUS="SUCCESS" ;;
  2) CURRENT_STATUS="DRIFT" ;;
  *) CURRENT_STATUS="FAILURE" ;;
esac

echo "Current status: $CURRENT_STATUS"

# Read the previous status from S3.
if aws s3api get-object \
  --bucket "$STATE_BUCKET" \
  --key "$STATUS_KEY" \
  /tmp/drift-previous.txt \
  >/dev/null 2>/tmp/drift-s3-error.txt; then

  PREVIOUS_STATUS=$(tr -d '\r\n' < /tmp/drift-previous.txt)

elif grep -Eqi 'NoSuchKey|Not Found|404' /tmp/drift-s3-error.txt; then
  PREVIOUS_STATUS="UNKNOWN"

else
  cat /tmp/drift-s3-error.txt >&2
  exit 1
fi

echo "Previous status: $PREVIOUS_STATUS"

if [ "$CURRENT_STATUS" = "$PREVIOUS_STATUS" ]; then
  echo "Status unchanged. No Slack notification."
  exit 0
fi

RUN_URL="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

case "$CURRENT_STATUS" in
  SUCCESS)
    MESSAGE="✅ Terraform infrastructure check is healthy."
    ;;
  DRIFT)
    MESSAGE="⚠️ Terraform detected infrastructure changes."
OAOAOAOAOAOAOAOAOA    ;;
  FAILURE)
OAOAOA    MESSAGE="❌ Terraform check failed."
OAOAOA    ;;
esac

OAOAOAMESSAGE="${MESSAGE}
Previous status: ${PREVIOUS_STATUS}
Report: ${RUN_URL}"

OAOAOAPAYLOAD=$(python3 -c \
  'import json,sys; print(json.dumps({"text": sys.stdin.read()}))' \
  <<< "$MESSAGE")

curl --fail-with-body --silent --show-error \
  -X POST \
  -H "Content-Type: application/json" \
  --data "$PAYLOAD" \
  "$SLACK_WEBHOOK_URL"

printf '%s\n' "$CURRENT_STATUS" > /tmp/drift-current.txt

aws s3 cp \
  /tmp/drift-current.txt \
  "s3://${STATE_BUCKET}/${STATUS_KEY}"

echo "Slack notification sent. Status saved."

