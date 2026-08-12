#!/usr/bin/env bash
# Libera kernel test suite. Exits non-zero on any assertion failure.
set -euo pipefail
cd "$(dirname "$0")"
exec mojo run -I . tests/run_all.mojo
