#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O Sources/Protocol.swift Sources/Crypto.swift Sources/Responses.swift Sources/Localization.swift Sources/Parameters.swift Sources/Guard.swift Tests/main.swift -o build/selftest
./build/selftest
