//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import Foundation

struct HistoryPagingState {
    let pageSize: Int
    private(set) var loadedCount: Int = 0
    private(set) var hasMore: Bool = true
    private(set) var isLoadingMore: Bool = false

    mutating func reset() {
        loadedCount = 0
        hasMore = true
        isLoadingMore = false
    }

    mutating func beginLoadingMore() -> Bool {
        guard hasMore, !isLoadingMore else { return false }
        isLoadingMore = true
        return true
    }

    mutating func finishLoadingMore(loaded pageCount: Int) {
        loadedCount += pageCount
        hasMore = pageCount == pageSize
        isLoadingMore = false
    }

    mutating func replaceLoadedHistory(count: Int, hasMore: Bool) {
        loadedCount = max(0, count)
        self.hasMore = hasMore
        isLoadingMore = false
    }

    mutating func cancelLoadingMore() {
        isLoadingMore = false
    }
}
