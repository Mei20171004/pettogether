#!/bin/zsh
set -euo pipefail

readonly FLUTTER_ROOT_DIR="${0:A:h:h}"
readonly DEVICE_A="${COPAW_LT7_DEVICE_A:?Set COPAW_LT7_DEVICE_A to the first iOS Simulator UDID}"
readonly DEVICE_B="${COPAW_LT7_DEVICE_B:?Set COPAW_LT7_DEVICE_B to the second iOS Simulator UDID}"
readonly RUN_ID="${COPAW_LT7_RUN_ID:?Set a synthetic lowercase run ID}"
readonly INVITE_CODE="${COPAW_LT7_INVITE_CODE:?Set a synthetic six-character invite code}"
readonly ISOLATION_CONFIRMED="${COPAW_LT7_ISOLATED_EXPORT_CONFIRMED:-no}"
readonly RUN_AUTHORIZED="${COPAW_LT7_COORDINATED_RUN_AUTHORIZED:-no}"
readonly AUTH_PORT=9199
readonly FIRESTORE_PORT=8180
readonly FUNCTIONS_PORT=5101

if [[ "${ISOLATION_CONFIRMED}" != "yes" || "${RUN_AUTHORIZED}" != "yes" ]]; then
  print -u2 "LT7 requires isolated-export confirmation and coordinated-run authorization."
  exit 2
fi

# Rules restrict invite codes to the unambiguous alphabet, so an otherwise
# reasonable-looking code fails deep inside the first coordinated phase.
if [[ ! "${INVITE_CODE}" =~ '^[A-Z2-9]{6}$' ]]; then
  print -u2 "LT7 invite code must be six characters from A-Z and 2-9."
  exit 2
fi

if [[ "${DEVICE_A}" == "${DEVICE_B}" ]]; then
  print -u2 "LT7 requires two different iOS Simulator devices."
  exit 2
fi

for port in "${AUTH_PORT}" "${FIRESTORE_PORT}" "${FUNCTIONS_PORT}"; do
  if ! lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    print -u2 "The isolated LT7 Firebase port ${port} is not listening."
    exit 2
  fi
done

for device in "${DEVICE_A}" "${DEVICE_B}"; do
  if ! xcrun simctl getenv "${device}" SIMULATOR_UDID >/dev/null 2>&1; then
    print -u2 "LT7 device ${device} is not a booted iOS Simulator."
    exit 2
  fi
  if xcrun simctl get_app_container \
    "${device}" com.copaw.demo.local app >/dev/null 2>&1; then
    print -u2 "Remove the existing com.copaw.demo.local sandbox before LT7."
    exit 2
  fi
  # Firebase Auth persists its session in the Keychain, which survives an app
  # uninstall. A leftover anonymous session would silently defeat the clean
  # identity precondition this phase is supposed to prove.
  if ! xcrun simctl keychain "${device}" reset >/dev/null 2>&1; then
    print -u2 "LT7 could not reset the Keychain on ${device}."
    exit 2
  fi
done

readonly AUTH_INVENTORY="$(
  curl -fsS -X POST \
    -H 'Authorization: Bearer owner' \
    -H 'Content-Type: application/json' \
    --data '{}' \
    "http://127.0.0.1:${AUTH_PORT}/identitytoolkit.googleapis.com/v1/projects/demo-copaw/accounts:query?key=local-api-key"
)"
if ! /usr/bin/python3 -c '
import json, sys
inventory = json.load(sys.stdin)
count = inventory.get("recordsCount")
users = inventory.get("userInfo", [])
raise SystemExit(0 if count in (0, "0") and users == [] else 1)
' <<<"${AUTH_INVENTORY}"; then
  print -u2 "LT7 Auth is not clean; use a fresh isolated Emulator suite."
  exit 2
fi

readonly FIRESTORE_DOCUMENTS_URL="http://127.0.0.1:${FIRESTORE_PORT}/v1/projects/demo-copaw/databases/(default)/documents"
readonly GENERATION_GATE="$(
  curl -fsS \
    -H 'Authorization: Bearer owner' \
    "${FIRESTORE_DOCUMENTS_URL}/systemConfig/notificationIntentGenerationV2"
)"
if ! /usr/bin/python3 -c '
import json, sys
fields = json.load(sys.stdin).get("fields", {})
expected = {"schemaVersion", "enabled", "projectID", "cutoverAt", "updatedBy", "updatedAt"}
valid = (
    set(fields) == expected
    and fields["schemaVersion"].get("integerValue") == "1"
    and fields["enabled"].get("booleanValue") is True
    and fields["projectID"].get("stringValue") == "demo-copaw"
    and bool(fields["cutoverAt"].get("timestampValue"))
    and bool(fields["updatedBy"].get("stringValue"))
    and bool(fields["updatedAt"].get("timestampValue"))
)
raise SystemExit(0 if valid else 1)
' <<<"${GENERATION_GATE}"; then
  print -u2 "LT7 requires a valid enabled notificationIntentGenerationV2 fixture."
  exit 2
fi
readonly DISPATCH_STATUS="$(
  curl -sS \
    -H 'Authorization: Bearer owner' \
    -o /dev/null -w '%{http_code}' \
    "${FIRESTORE_DOCUMENTS_URL}/systemConfig/notificationDispatchV2"
)"
if [[ "${DISPATCH_STATUS}" != "404" ]]; then
  print -u2 "LT7 notificationDispatchV2 must be absent."
  exit 2
fi

# A Functions discovery timeout leaves Auth and Firestore listening while every
# callable is missing, so the harness refuses to run against a half-loaded backend.
for callable in mutateTaskResponsibility mutateHandoffSession leaveHousehold; do
  probe_status="$(
    curl -sS -o /dev/null -w '%{http_code}' \
      "http://127.0.0.1:${FUNCTIONS_PORT}/demo-copaw/asia-northeast1/${callable}"
  )"
  if [[ "${probe_status}" == "404" ]]; then
    print -u2 "LT7 callable ${callable} is not loaded; restart the isolated suite."
    exit 2
  fi
done

# A rebuilt mirror costs several minutes per client, so an explicit reusable
# root makes a retry cheap. It is only reused when both clients are present.
if [[ -n "${COPAW_LT7_MIRROR_ROOT:-}" ]]; then
  mkdir -p "${COPAW_LT7_MIRROR_ROOT}"
  readonly TEMP_ROOT="${COPAW_LT7_MIRROR_ROOT}"
  readonly REUSING_MIRRORS=yes
else
  readonly TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/copaw-lt7-ios.XXXXXX")"
  readonly REUSING_MIRRORS=no
fi
readonly MIRROR_A="${TEMP_ROOT}/client-a"
readonly MIRROR_B="${TEMP_ROOT}/client-b"
# Failed runs keep their mirrors and logs; a rebuild costs several minutes and
# the logs are the only record of what the coordinated clients observed.
cleanup() {
  if [[ "${REUSING_MIRRORS}" == "yes" ]]; then
    print -u2 "LT7 kept its reusable mirrors and logs at ${TEMP_ROOT}"
  elif [[ "${LT7_RUN_SUCCEEDED:-no}" == "yes" ]]; then
    rm -rf -- "${TEMP_ROOT}"
  else
    print -u2 "LT7 kept its mirrors and logs at ${TEMP_ROOT}"
  fi
}
trap 'cleanup' EXIT

prepare_mirror() {
  local destination="$1"
  if [[ "${REUSING_MIRRORS}" == "yes" && -f "${destination}/pubspec.yaml" ]]; then
    print "LT7_MIRROR reused=${destination}"
    return 0
  fi
  mkdir -p "${destination}"
  rsync -a \
    --exclude '.dart_tool' \
    --exclude 'build' \
    --exclude 'ios/Flutter/ephemeral' \
    --exclude 'GoogleService-Info.plist' \
    --exclude 'google-services.json' \
    "${FLUTTER_ROOT_DIR}/" "${destination}/"
  (cd "${destination}" && flutter pub get)
}

run_client() {
  local mirror="$1"
  local device="$2"
  local role="$3"
  local phase="$4"
  local log_file="$5"
  local entry="${6:-integration_test/firebase_two_process_acceptance_test.dart}"
  (
    cd "${mirror}"
    flutter test \
      --no-uninstall \
      --flavor local \
      "${entry}" \
      -d "${device}" \
      --dart-define=COPAW_LT7_ROLE="${role}" \
      --dart-define=COPAW_LT7_PHASE="${phase}" \
      --dart-define=COPAW_LT7_RUN_ID="${RUN_ID}" \
      --dart-define=COPAW_LT7_INVITE_CODE="${INVITE_CODE}" \
      --dart-define=COPAW_FIREBASE_AUTH_PORT=9199 \
      --dart-define=COPAW_FIREBASE_FIRESTORE_PORT=8180 \
      --dart-define=COPAW_FIREBASE_FUNCTIONS_PORT=5101
  ) >"${log_file}" 2>&1
}

run_phase() {
  local phase="$1"
  local log_a="${TEMP_ROOT}/${phase}-a.log"
  local log_b="${TEMP_ROOT}/${phase}-b.log"
  local pid_a
  local pid_b
  if [[ "${phase}" == "offline" ]]; then
    run_client "${MIRROR_B}" "${DEVICE_B}" B "${phase}" "${log_b}" &
    pid_b=$!
    local ready=0
    for _ in {1..60}; do
      if grep -q 'LT7_READY_OFFLINE' "${log_b}" 2>/dev/null; then
        ready=1
        break
      fi
      if ! kill -0 "${pid_b}" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if [[ "${ready}" -ne 1 ]]; then
      wait "${pid_b}" || true
      print -u2 "LT7 offline client B did not reach its cache boundary."
      sed -n '1,240p' "${log_b}" >&2
      return 1
    fi
    run_client "${MIRROR_A}" "${DEVICE_A}" A "${phase}" "${log_a}" &
    pid_a=$!
  else
    run_client "${MIRROR_A}" "${DEVICE_A}" A "${phase}" "${log_a}" &
    pid_a=$!
    # Bootstrap is the only phase where both sides must be live at once: client B
    # joins the household client A is creating. Later phases read a membership
    # that already exists, so client B waits for client A to finish building.
    # Two concurrent Xcode builds exhaust memory and get SIGKILLed.
    if [[ "${phase}" != "bootstrap" ]]; then
      for _ in {1..150}; do
        if grep -q 'Xcode build done' "${log_a}" 2>/dev/null; then
          break
        fi
        if ! kill -0 "${pid_a}" 2>/dev/null; then
          break
        fi
        sleep 2
      done
    fi
    run_client "${MIRROR_B}" "${DEVICE_B}" B "${phase}" "${log_b}" &
    pid_b=$!
  fi
  local phase_status=0
  wait "${pid_a}" || phase_status=$?
  wait "${pid_b}" || phase_status=$?
  sed -n '/LT7_RECEIPT/p' "${log_a}"
  sed -n '/LT7_RECEIPT/p' "${log_b}"
  if [[ "${phase_status}" -ne 0 ]]; then
    print -u2 "LT7 ${phase} failed. Client logs follow."
    sed -n '1,240p' "${log_a}" >&2
    sed -n '1,240p' "${log_b}" >&2
    return "${phase_status}"
  fi
}

identity_field() {
  local phase="$1"
  local role="$2"
  local field="$3"
  local role_name="${role:l}"
  sed -n '/LT7_RECEIPT checkpoint=identity/p' \
    "${TEMP_ROOT}/${phase}-${role_name}.log" | tail -n 1 | awk -v key="${field}" '
      {
        for (index = 1; index <= NF; index += 1) {
          split($index, pair, "=")
          if (pair[1] == key) print pair[2]
        }
      }
    '
}

verify_identity_convergence() {
  local uid_a="$(identity_field bootstrap A uidHash)"
  local uid_b="$(identity_field bootstrap B uidHash)"
  local household="$(identity_field bootstrap A householdHash)"
  if [[ -z "${uid_a}" || -z "${uid_b}" || -z "${household}" ||
        "${uid_a}" == "${uid_b}" ]]; then
    print -u2 "LT7 requires two distinct non-empty persisted identities."
    return 1
  fi
  for phase in bootstrap reconnect source offline; do
    if [[ "$(identity_field "${phase}" A uidHash)" != "${uid_a}" ||
          "$(identity_field "${phase}" B uidHash)" != "${uid_b}" ||
          "$(identity_field "${phase}" A householdHash)" != "${household}" ||
          "$(identity_field "${phase}" B householdHash)" != "${household}" ||
          "$(identity_field "${phase}" A members)" != "2" ||
          "$(identity_field "${phase}" B members)" != "2" ]]; then
      print -u2 "LT7 identity or household convergence failed in ${phase}."
      return 1
    fi
  done
  print "LT7_IDENTITY uidDistinct=true uidStable=true householdStable=true members=2"
}

warm_up_client() {
  local mirror="$1"
  local device="$2"
  local role="$3"
  local log_file="${TEMP_ROOT}/warmup-${role:l}.log"
  # Building both clients at once exhausts memory and Xcode is SIGKILLed, so
  # each client is built and connectivity-checked serially before any phase.
  run_client "${mirror}" "${device}" "${role}" warmup "${log_file}" \
    integration_test/lt7_connectivity_probe_test.dart
  if ! grep -q 'LT7_PROBE step=reachable' "${log_file}"; then
    print -u2 "LT7 client ${role} could not reach the isolated Emulator."
    sed -n '1,120p' "${log_file}" >&2
    return 1
  fi
  print "LT7_WARMUP role=${role} reachable=true"
}

prepare_mirror "${MIRROR_A}"
prepare_mirror "${MIRROR_B}"
warm_up_client "${MIRROR_A}" "${DEVICE_A}" A
warm_up_client "${MIRROR_B}" "${DEVICE_B}" B
run_phase bootstrap
run_phase reconnect
run_phase source
run_phase offline
verify_identity_convergence
LT7_RUN_SUCCEEDED=yes
