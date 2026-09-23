#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/tests
./scripts/swiftc.sh Sources/MacBar/Models.swift Tests/Smoke/main.swift -o .build/tests/ModelTests
.build/tests/ModelTests
