#!/bin/zsh
set -euo pipefail

readonly REPOSITORY_ROOT="${0:A:h:h}"
exec "${REPOSITORY_ROOT}/scripts/node22_exec.sh" \
    "${REPOSITORY_ROOT}/scripts/lt7_firebase.mjs" emulators
