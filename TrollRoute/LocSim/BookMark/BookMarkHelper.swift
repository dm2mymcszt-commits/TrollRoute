import Foundation
import SwiftUI

func bookmarkStore() throws -> FavoritesStore {
    guard let store = FavoritesStore.shared else { throw FavoritesStore.Failure.unavailable }
    return store
}

func BookMarkSave(lat: Double, long: Double, name: String) -> Bool {
    do {
        try bookmarkStore().save(.init(name: name, latitude: lat, longitude: long))
        SharedPlaceSignal.post()
        successVibrate()
        return true
    } catch { return false }
}

func BookMarkRetrieve() throws -> [[String: Any]] {
    try bookmarkStore().read().map(\.dictionary)
}
