import Foundation

/// Only value ranges are cached, never chapter bodies or Core Text frames.
/// The budget accounts for slice storage; shared chapter-ID strings are bounded
/// separately by the entry cap. Oversized layouts remain usable but are not cached.
struct PageRangeCache<Key: Hashable> {
    private var values: [Key: [PageSlice]] = [:]
    private var order: [Key] = []
    let budget: Int
    let capacity: Int
    init(budget: Int, capacity: Int) { self.budget = budget; self.capacity = capacity }
    var estimatedBytes: Int { values.values.reduce(0) { $0 + $1.count * MemoryLayout<PageSlice>.stride } }
    var count: Int { values.count }

    mutating func value(for key: Key) -> [PageSlice]? {
        guard let value = values[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return value
    }
    mutating func insert(_ pages: [PageSlice], for key: Key) {
        values.removeValue(forKey: key); order.removeAll { $0 == key }
        guard pages.count <= max(0, budget) / max(1, MemoryLayout<PageSlice>.stride), capacity > 0 else { return }
        values[key] = pages; order.append(key)
        while values.count > capacity || estimatedBytes > budget {
            guard let oldest = order.first else { break }
            values.removeValue(forKey: oldest); order.removeFirst()
        }
    }
    mutating func remove(where predicate: (Key) -> Bool) {
        for key in Array(values.keys) where predicate(key) { values.removeValue(forKey: key) }
        order.removeAll(where: predicate)
    }
    mutating func removeAll() { values.removeAll(); order.removeAll() }
}
