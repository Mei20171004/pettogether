#!/bin/zsh
# LT7-AC04: repeatable local preservation acceptance.
#
# It seeds the synthetic canonical-plus-legacy corpus into an isolated Emulator
# suite, exports it through the guarded hub, proves that out-of-schema and
# in-schema drift are both detected, restores the signed export, and reconciles
# the content-free receipt. It never touches the shared suite, a non-demo
# project, or any remote Firebase surface.
set -euo pipefail

readonly REPOSITORY_ROOT="${0:A:h:h}"
readonly EXPORT_DIRECTORY="${1:?Usage: lt7_snapshot_acceptance.sh /absolute/new/export-directory}"
readonly AUTH_HOST=127.0.0.1:9399
readonly FIRESTORE_HOST=127.0.0.1:8280
readonly HUB_PORT=4700
: "${COPAW_SNAPSHOT_RECEIPT_KEY:?Set COPAW_SNAPSHOT_RECEIPT_KEY to a local receipt key}"

if [[ -e "${EXPORT_DIRECTORY}" ]]; then
  print -u2 "LT7 export target must not already exist."
  exit 2
fi
for port in 9399 8280 4700 4701; do
  if lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    print -u2 "The isolated LT7 snapshot port ${port} is already in use."
    exit 2
  fi
done

cd "${REPOSITORY_ROOT}"

readonly LOG_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/copaw-lt7-snapshot.XXXXXX")"
print "LT7_SNAPSHOT logs=${LOG_DIRECTORY}"

fail_with_logs() {
  print -u2 "LT7 snapshot acceptance failed during ${1}."
  for log_file in "${LOG_DIRECTORY}"/*(.N); do
    print -u2 -- "--- ${log_file} ---"
    tail -n 40 "${log_file}" >&2
  done
  exit 1
}
SUITE_PID=""
stop_suite() {
  if [[ -n "${SUITE_PID}" ]] && kill -0 "${SUITE_PID}" 2>/dev/null; then
    kill -TERM "${SUITE_PID}" 2>/dev/null || true
    wait "${SUITE_PID}" 2>/dev/null || true
  fi
  SUITE_PID=""
  # A leftover Emulator would silently poison the next run, so the isolated
  # ports must be free again before the script continues or exits.
  for _ in {1..30}; do
    if ! lsof -nP -iTCP:9399,8280,4700,4701 -sTCP:LISTEN >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  print -u2 "The isolated LT7 snapshot ports did not shut down."
  return 1
}
trap 'stop_suite' EXIT

start_suite() {
  local operation="$1"
  local log_file="$2"
  shift 2
  # No subshell wrapper: node22_exec.sh execs the pinned runtime in place, so
  # the recorded PID is the guarded driver itself and a SIGTERM reaches the
  # Firebase process it supervises instead of orphaning it on the ports.
  ./scripts/node22_exec.sh \
    scripts/lt7_firebase_supervisor.mjs "${operation}" "$@" \
    >"${log_file}" 2>&1 &
  SUITE_PID=$!
  for _ in {1..90}; do
    # The hub answers before Auth and Firestore accept traffic, so readiness
    # means every surface the acceptance steps actually use is listening.
    if curl -fsS "http://127.0.0.1:${HUB_PORT}/emulators" >/dev/null 2>&1 &&
       curl -fsS "http://${AUTH_HOST}/emulator/v1/projects/demo-copaw/config" \
         -H 'Authorization: Bearer owner' >/dev/null 2>&1 &&
       curl -fsS "http://${FIRESTORE_HOST}/" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "${SUITE_PID}" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  print -u2 "The isolated LT7 snapshot suite did not become ready."
  sed -n '1,80p' "${log_file}" >&2
  return 1
}

snapshot_action() {
  (
    FIRESTORE_EMULATOR_HOST="${FIRESTORE_HOST}" \
    FIREBASE_AUTH_EMULATOR_HOST="${AUTH_HOST}" \
    LT7_SNAPSHOT_ACTION="$1" \
      ./scripts/node22_exec.sh --test tests/lt7.snapshot_emulator.test.mjs
  ) >"${LOG_DIRECTORY}/$1.log" 2>&1
}

receipt() {
  (
    FIRESTORE_EMULATOR_HOST="${FIRESTORE_HOST}" \
    FIREBASE_AUTH_EMULATOR_HOST="${AUTH_HOST}" \
      npm run --silent lt7:snapshot-receipt -- \
        --input tests/fixtures/lt7-preservation-sentinels.json
  ) >"$1" 2>"$1.err"
}

start_suite snapshot "${LOG_DIRECTORY}/suite-seed.log"
snapshot_action seed || fail_with_logs "seed"
receipt "${LOG_DIRECTORY}/receipt-before.json" || fail_with_logs "baseline receipt"
print "LT7_SNAPSHOT checkpoint=seeded"

npm run --silent lt7:export -- "${EXPORT_DIRECTORY}"
print "LT7_SNAPSHOT checkpoint=exported"

snapshot_action probe || fail_with_logs "out-of-schema probe"
if receipt "${LOG_DIRECTORY}/receipt-probe.json"; then
  print -u2 "LT7 out-of-schema drift was fingerprinted instead of refused."
  exit 1
fi
print "LT7_SNAPSHOT checkpoint=outOfSchemaRefused"

snapshot_action mutate || fail_with_logs "in-schema mutation"
receipt "${LOG_DIRECTORY}/receipt-mutated.json" || fail_with_logs "mutated receipt"
stop_suite

start_suite restore "${LOG_DIRECTORY}/suite-restore.log" "${EXPORT_DIRECTORY}"
receipt "${LOG_DIRECTORY}/receipt-after.json" || fail_with_logs "restored receipt"
stop_suite

./scripts/node22_exec.sh \
  scripts/lt7_snapshot_reconcile.mjs \
  "${LOG_DIRECTORY}/receipt-before.json" \
  "${LOG_DIRECTORY}/receipt-mutated.json" \
  "${LOG_DIRECTORY}/receipt-after.json"
