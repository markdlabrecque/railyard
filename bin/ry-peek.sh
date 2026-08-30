#!/usr/bin/env bash
# Show an engine's recent terminal output. usage: ry-peek.sh <id>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac
[ -n "${1:-}" ] || ry_die "need <id>"
ry_backend_peek "$1"
