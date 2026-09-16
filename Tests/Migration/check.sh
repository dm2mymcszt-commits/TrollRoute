#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/migration-qa
xcrun swiftc TrollRoute/Storage/SharedPreferences.swift TrollRoute/Storage/FavoritesStore.swift TrollRoute/Storage/LegacyMigration.swift Tests/Migration/main.swift -o build/migration-qa/tests
build/migration-qa/tests
