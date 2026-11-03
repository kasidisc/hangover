#!/bin/bash
# Builds the app and zips it for a GitHub release: dist/Hangover.zip
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/test.sh
scripts/build.sh
mkdir -p dist && rm -f dist/Hangover.zip
ditto -c -k --keepParent build/Hangover.app dist/Hangover.zip
echo "packaged dist/Hangover.zip ($(du -h dist/Hangover.zip | cut -f1))"
