import Dispatch

/// Follows the packet log of a controller the service holds, for the tools that cannot open the
/// device themselves.
package enum PacketLogStream {
  /// Reads snapshots through `read` and passes each entry that appears after the first snapshot to
  /// `onEntry`, until `duration` seconds pass; without a duration it runs until cancelled.
  ///
  /// The service's ring keeps 200 entries, so the loop polls faster than the ring turns over.
  package static func follow(
    duration: Double?,
    interval: UInt64 = 16_000_000,
    read: () async throws -> [PacketLogEntry],
    onEntry: (PacketLogEntry) throws -> Void
  ) async throws {
    var cursor = PacketLogSnapshotCursor(snapshot: try await read())
    let start = DispatchTime.now().uptimeNanoseconds
    let limit = duration.map { UInt64($0 * 1_000_000_000) }
    while limit.map({ DispatchTime.now().uptimeNanoseconds - start < $0 }) ?? true {
      for entry in cursor.consume(snapshot: try await read()) { try onEntry(entry) }
      try await Task.sleep(nanoseconds: interval)
    }
  }
}
