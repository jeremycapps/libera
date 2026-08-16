#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

npm --prefix facia test
npm --prefix facia run verify
./run_tests.sh
