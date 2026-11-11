import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite("MultiTapEntries")
struct MultiTapEntriesTests {
  private let key = RemappingDestination.keyboard(key: .space, modifiers: [])

  private func entry(_ count: Int, _ windowMs: Double = 200) -> RemappingMultiTap {
    RemappingMultiTap(count: count, windowMs: windowMs, destination: key)
  }

  @Test
  func addingTakesLowestUnusedCountUntilAllAreUsed() {
    var entries: [RemappingMultiTap] = []
    for _ in 0..<6 { entries = MultiTapEntries.adding(to: entries, destination: key) }
    #expect(entries.map(\.count) == [2, 3, 4, 5])
    #expect(MultiTapEntries.unusedCounts(in: entries).isEmpty)
  }

  @Test
  func replacingKeepsCountsUniqueAndSorted() {
    let entries = [entry(2), entry(4)]
    #expect(MultiTapEntries.replacing(count: 4, with: entry(2), in: entries) == entries)
    let moved = MultiTapEntries.replacing(count: 2, with: entry(5, 300), in: entries)
    #expect(moved.map(\.count) == [4, 5])
    #expect(moved.longestWindowMs == 300)
  }

  @Test
  func removingDropsOnlyThatCount() {
    #expect(MultiTapEntries.removing(count: 2, from: [entry(2), entry(3)]) == [entry(3)])
  }
}
