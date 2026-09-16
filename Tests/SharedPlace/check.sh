#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QA_DIR="$PWD/build/shared-place-qa"
mkdir -p "$QA_DIR"
xcrun swiftc TrollRoute/Storage/SharedPreferences.swift TrollRoute/Storage/FavoritesStore.swift TrollRoute/LocSim/PlaceModels.swift TrollRoute/LocSim/PlaceInput.swift \
  TrollRoute/LocSim/AddressQuery.swift TrollRoute/LocSim/PlaceSearch.swift \
  TrollRoute/LocSim/CoordTransform.swift TrollRoute/LocSim/SharedPlace.swift \
  Tests/SharedPlace/main.swift -o "$QA_DIR/share-tests"
"$QA_DIR/share-tests"

xcrun swiftc -parse-as-library TrollRoute/Storage/SharedPreferences.swift \
  TrollRoute/LocSim/RouteElevation.swift TrollRoute/LocSim/Altitude.swift \
  TrollRoute/LocSim/LocationSession.swift TrollRoute/LocSim/DirectLocationMove.swift \
  Tests/SharedPlace/DirectMove.swift -o "$QA_DIR/direct-move-tests"
"$QA_DIR/direct-move-tests"

xcrun swiftc TrollRoute/Storage/SharedPreferences.swift TrollRoute/Storage/FavoritesStore.swift \
  Tests/SharedPlace/Favorites.swift -o "$QA_DIR/favorite-store-tests"
"$QA_DIR/favorite-store-tests"
