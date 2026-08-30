#!/bin/zsh
set -euo pipefail

readonly PROJECT_ID="${COPAW_DEMO_PROJECT_ID:-copaw-94a57}"
readonly HOUSEHOLD_ID="${COPAW_DEMO_HOUSEHOLD_ID:-copaw-50s-demo}"
readonly INVITE_CODE="${COPAW_DEMO_INVITE_CODE:?Set COPAW_DEMO_INVITE_CODE to the six-character demo invite code}"
readonly ALEX_ID="${COPAW_DEMO_A_UID:?Set COPAW_DEMO_A_UID to device A's Firebase Auth UID}"
readonly MAYA_ID="${COPAW_DEMO_B_UID:?Set COPAW_DEMO_B_UID to device B's Firebase Auth UID}"
readonly BUNDLE_ID="com.copaw.demo"
readonly APP_PATH="${COPAW_DEMO_APP_PATH:-}"
readonly CONFIG_ROOT="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly FIREBASE_CONFIG="${COPAW_FIREBASE_CONFIG:-${CONFIG_ROOT}/configstore/firebase-tools.json}"
readonly API_ROOT="https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents"
readonly HOUSEHOLD_ROOT="${API_ROOT}/households/${HOUSEHOLD_ID}"

booted_devices=("${(@f)$(/usr/bin/xcrun simctl list devices booted -j | /usr/bin/jq -r '.devices[][] | select(.state == "Booted" and .isAvailable == true) | .udid')}")
readonly DEVICE_A="${COPAW_DEMO_DEVICE_A:-${booted_devices[1]:-}}"
readonly DEVICE_B="${COPAW_DEMO_DEVICE_B:-${booted_devices[2]:-}}"

if [[ -z "$DEVICE_A" || -z "$DEVICE_B" || "$DEVICE_A" == "$DEVICE_B" ]]; then
    print -u2 "Boot two simulators or set COPAW_DEMO_DEVICE_A and COPAW_DEMO_DEVICE_B."
    exit 1
fi

access_token="${COPAW_FIREBASE_ACCESS_TOKEN:-}"
if [[ -z "$access_token" && -f "$FIREBASE_CONFIG" ]]; then
    access_token=$(/usr/bin/jq -r '.tokens.access_token // empty' "$FIREBASE_CONFIG")
fi
if [[ -z "$access_token" ]]; then
    print -u2 "Firebase access token is unavailable. Set COPAW_FIREBASE_ACCESS_TOKEN or run firebase login first."
    exit 1
fi

/usr/bin/curl -sS -X PATCH \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    "${API_ROOT}/households/${HOUSEHOLD_ID}" \
    -d "{\"fields\":{\"id\":{\"stringValue\":\"${HOUSEHOLD_ID}\"},\"name\":{\"stringValue\":\"Copaw 50s Demo\"},\"petName\":{\"stringValue\":\"Mochi\"},\"inviteCode\":{\"stringValue\":\"${INVITE_CODE}\"},\"timeZoneIdentifier\":{\"stringValue\":\"Asia/Tokyo\"},\"ownerID\":{\"stringValue\":\"${ALEX_ID}\"},\"createdAt\":{\"timestampValue\":\"2026-08-08T07:00:00Z\"}}}" >/dev/null

/usr/bin/curl -sS -X PATCH \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    "${API_ROOT}/inviteCodes/${INVITE_CODE}" \
    -d "{\"fields\":{\"householdID\":{\"stringValue\":\"${HOUSEHOLD_ID}\"},\"createdBy\":{\"stringValue\":\"${ALEX_ID}\"},\"createdAt\":{\"timestampValue\":\"2026-08-08T07:00:00Z\"},\"active\":{\"booleanValue\":true}}}" >/dev/null

for member_entry in "${ALEX_ID}:Alex" "${MAYA_ID}:Maya"; do
    member_id=${member_entry%%:*}
    member_name=${member_entry#*:}
    /usr/bin/curl -sS -X PATCH \
        -H "Authorization: Bearer ${access_token}" \
        -H "Content-Type: application/json" \
        "${HOUSEHOLD_ROOT}/members/${member_id}" \
        -d "{\"fields\":{\"id\":{\"stringValue\":\"${member_id}\"},\"displayName\":{\"stringValue\":\"${member_name}\"},\"inviteCode\":{\"stringValue\":\"${INVITE_CODE}\"},\"joinedAt\":{\"timestampValue\":\"2026-08-08T07:00:00Z\"}}}" >/dev/null
done

task_documents=$(/usr/bin/curl -sS \
    -H "Authorization: Bearer ${access_token}" \
    "${HOUSEHOLD_ROOT}/tasks?pageSize=100")

while IFS= read -r document_name; do
    [[ -z "$document_name" ]] && continue
    /usr/bin/curl -sS -X DELETE \
        -H "Authorization: Bearer ${access_token}" \
        "https://firestore.googleapis.com/v1/${document_name}" >/dev/null
done < <(print -r -- "$task_documents" | /usr/bin/jq -r '
    (.documents // [])[].name
')

routine_documents=$(/usr/bin/curl -sS \
    -H "Authorization: Bearer ${access_token}" \
    "${HOUSEHOLD_ROOT}/routines?pageSize=100")

while IFS= read -r document_name; do
    [[ -z "$document_name" ]] && continue
    /usr/bin/curl -sS -X DELETE \
        -H "Authorization: Bearer ${access_token}" \
        "https://firestore.googleapis.com/v1/${document_name}" >/dev/null
done < <(print -r -- "$routine_documents" | /usr/bin/jq -r '
    (.documents // [])[]
    | select(.fields.id.stringValue != "demo-routine-tue-fri")
    | .name
')

/usr/bin/curl -sS -X PATCH \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    "${HOUSEHOLD_ROOT}/routines/demo-routine-tue-fri" \
    -d '{
      "fields": {
        "id": {"stringValue": "demo-routine-tue-fri"},
        "title": {"stringValue": "Morning food"},
        "category": {"stringValue": "feeding"},
        "priority": {"stringValue": "normal"},
        "frequency": {"stringValue": "selectedDays"},
        "weekdays": {"arrayValue": {"values": [
          {"integerValue": "3"},
          {"integerValue": "6"}
        ]}},
        "hour": {"integerValue": "7"},
        "minute": {"integerValue": "30"},
        "startDate": {"timestampValue": "2026-08-07T15:00:00Z"},
        "timeZoneIdentifier": {"stringValue": "Asia/Tokyo"},
        "createdByID": {"stringValue": "'"${ALEX_ID}"'"},
        "createdByName": {"stringValue": "Alex"},
        "isActive": {"booleanValue": true},
        "createdAt": {"timestampValue": "2026-08-08T06:55:00Z"}
      }
    }' >/dev/null

if [[ -n "$APP_PATH" && -d "$APP_PATH" ]]; then
    /usr/bin/xcrun simctl install "$DEVICE_A" "$APP_PATH"
    /usr/bin/xcrun simctl install "$DEVICE_B" "$APP_PATH"
fi

/usr/bin/xcrun simctl terminate "$DEVICE_A" "$BUNDLE_ID" >/dev/null 2>&1 || true
/usr/bin/xcrun simctl terminate "$DEVICE_B" "$BUNDLE_ID" >/dev/null 2>&1 || true
/usr/bin/xcrun simctl launch "$DEVICE_A" "$BUNDLE_ID" --copaw-demo-household "$HOUSEHOLD_ID" >/dev/null
/usr/bin/xcrun simctl launch "$DEVICE_B" "$BUNDLE_ID" --copaw-demo-reset-session >/dev/null
/usr/bin/open -a Simulator

print "50-second demo prepared: invite ${INVITE_CODE}, A=Alex, B=Maya."
