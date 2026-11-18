import Foundation

extension EndpointServer {
  /// The streams that a `Subscription` names.
  enum SubscriptionStream: String {
    case controllers = "Controllers"
    case profiles = "Profiles"
    case mods = "Mods"
  }

  /// The nanoseconds between two reads of a list that a `Profiles` or `Mods` subscription watches.
  static let listPollNanoseconds: UInt64 = 500_000_000

  /// Sends `connection` the list that `read` returns, then again each time it differs from the one
  /// last sent, until the returned task is cancelled or the connection closes.
  ///
  /// A failed read sends nothing and is tried again at the next poll, so a service that is not
  /// ready yet delivers the list once it is.
  func watchList<List: Encodable & Equatable & Sendable>(
    _ connection: EndpointConnection,
    read: @escaping @Sendable () async throws -> List
  ) -> Task<Void, Never> {
    Task {
      var sent: List?
      while !Task.isCancelled, !connection.isClosing {
        if let list = try? await read(), list != sent {
          sent = list
          connection.send(list, bounded: true)
        }
        try? await Task.sleep(nanoseconds: Self.listPollNanoseconds)
      }
    }
  }
}
