import OpenJoystickDriverKit

/// Edits the list of tap-count entries of one assignment in the behavior sheet.
enum MultiTapEntries {
  /// The window of a new entry in milliseconds.
  static let defaultWindowMs = 300.0

  /// The tap counts that no entry in `entries` uses, lowest first.
  static func unusedCounts(in entries: [RemappingMultiTap]) -> [Int] {
    let used = Set(entries.map(\.count))
    return RemappingMultiTap.countRange.filter { !used.contains($0) }
  }

  /// `entries` plus one entry for the lowest unused count, or `entries` when all counts are used.
  static func adding(
    to entries: [RemappingMultiTap],
    destination: RemappingDestination
  ) -> [RemappingMultiTap] {
    guard let count = unusedCounts(in: entries).first else { return entries }
    return
      (entries + [
        RemappingMultiTap(count: count, windowMs: defaultWindowMs, destination: destination)
      ]).sorted { $0.count < $1.count }
  }

  /// `entries` with the entry at `count` replaced, keeping the list sorted by count.
  ///
  /// The replacement takes `entry`'s count; a count that another entry holds leaves `entries`
  /// unchanged, so counts stay unique.
  static func replacing(
    count: Int,
    with entry: RemappingMultiTap,
    in entries: [RemappingMultiTap]
  ) -> [RemappingMultiTap] {
    if entry.count != count, entries.contains(where: { $0.count == entry.count }) {
      return entries
    }
    return entries.map { $0.count == count ? entry : $0 }.sorted { $0.count < $1.count }
  }

  /// `entries` without the entry at `count`.
  static func removing(count: Int, from entries: [RemappingMultiTap]) -> [RemappingMultiTap] {
    entries.filter { $0.count != count }
  }
}
