#!/bin/bash
# Builds and runs the engine test suite (plain swiftc).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -O -target "$(uname -m)-apple-macos13.0" Sources/Core/*.swift Tests/*.swift -o .build/core-tests
.build/core-tests
