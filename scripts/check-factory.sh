#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bash "$repo/tests/check-library.sh"
bash "$repo/tests/installers.sh"
bash "$repo/tests/native-literal-paths.sh"
bash "$repo/tests/native-regressions.sh"
bash "$repo/tests/native-runtime.sh"
bash "$repo/tests/add-issue.sh"
bash "$repo/tests/label-status.sh"
