#!/usr/bin/env bash
# Validates assets/db/vocab.db (see tools/data/validate_database.py for the checks).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p tools/data/out
python3 -I tools/data/validate_database.py assets/db/vocab.db tools/data/out/validation.json
