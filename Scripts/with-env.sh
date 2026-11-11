#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/Platform/environment.sh"
cd "$PROJECT_DIR"
exec "$@"
