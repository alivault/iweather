#!/bin/bash

set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

node --test tests/model.test.js
bash -n nws-weather.sh
node --check Model.js
jq empty manifest.json

if command -v shellcheck >/dev/null; then
  shellcheck --severity=warning nws-weather.sh check.sh
else
  echo "shellcheck not installed; skipped"
fi
