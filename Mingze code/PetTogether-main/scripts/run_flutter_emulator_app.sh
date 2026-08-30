#!/bin/zsh
set -euo pipefail

readonly REPOSITORY_ROOT="${0:A:h:h}"

cd "${REPOSITORY_ROOT}/copaw_flutter"
exec flutter run --target lib/main_emulator.dart "$@"
