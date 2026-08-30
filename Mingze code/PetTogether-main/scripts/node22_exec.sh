#!/bin/zsh
set -euo pipefail

readonly REPOSITORY_ROOT="${0:A:h:h}"
readonly REQUIRED_VERSION="22.23.2"
readonly PINNED_NODE="${REPOSITORY_ROOT}/node_modules/node/bin/node"

if [[ ! -x "${PINNED_NODE}" ]]; then
    print -u2 "Repository Node ${REQUIRED_VERSION} is missing. Run npm ci first."
    exit 1
fi

readonly ACTUAL_VERSION="$(${PINNED_NODE} --version)"
if [[ "${ACTUAL_VERSION}" != "v${REQUIRED_VERSION}" ]]; then
    print -u2 "Repository Node ${REQUIRED_VERSION} is required; found ${ACTUAL_VERSION}."
    exit 1
fi

exec "${PINNED_NODE}" "$@"
