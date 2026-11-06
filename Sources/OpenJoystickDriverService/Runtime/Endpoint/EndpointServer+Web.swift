import CryptoKit
import Darwin
import Foundation
import OpenJoystickDriverKit

/// The WebSocket on `127.0.0.1`, and the overlay pages on the same port.
extension EndpointServer {
  /// Saves the switch and the port and opens or closes the WebSocket; disabling closes every web
  /// connection with `E1001`.
  ///
  /// Nil keeps the saved port, and without one the system picks a free port; 0 picks a free port
  /// even when one is saved. The picked port is saved, so no fixed port is there for another
  /// program to take first.
  func setWebEnabled(_ enabled: Bool, port: Int?) throws {
    try lock.withLock {
      var file = try store.load()
      guard enabled else {
        file.web.enabled = false
        try store.save(file)
        stopWebListening()
        let error = EndpointError(code: .endpointDisabled, message: "The WebSocket was disabled.")
        for connection in connections.values where connection.kind == .web {
          connection.close(error)
        }
        return
      }
      let requested = port ?? file.web.port ?? 0
      guard requested == 0 || AccessWebSettings.ports.contains(requested) else {
        throw AccessGrantStoreError.portUnavailable(requested)
      }
      let keepsListener =
        port != 0 && (webListener.map { requested == 0 || requested == $0.port } ?? false)
      let listener = keepsListener ? nil : try openWebListener(port: requested)
      file.web = AccessWebSettings(enabled: true, port: listener?.port ?? webListener?.port ?? 0)
      do { try store.save(file) } catch {
        listener?.discard()
        throw error
      }
      if let listener {
        stopWebListening()
        startWebListening(listener)
      }
    }
  }

  /// A listening TCP socket on `127.0.0.1`, and the port it got.
  func openWebListener(port: Int) throws -> AcceptListener {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
    var reuse: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(UInt16(port).bigEndian)
    address.sin_addr = in_addr(s_addr: in_addr_t(0x7F00_0001).bigEndian)
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, length) == 0 && getsockname(descriptor, $0, &length) == 0
      }
    }
    guard bound, Darwin.listen(descriptor, 16) == 0 else {
      let error = errno
      Darwin.close(descriptor)
      if error == EADDRINUSE || error == EACCES {
        throw AccessGrantStoreError.portUnavailable(port)
      }
      throw LocalServiceRPCError.connectionFailed(error)
    }
    return try AcceptListener(
      listening: descriptor,
      port: Int(UInt16(bigEndian: address.sin_port)),
      acceptCall: acceptCall
    )
  }

  /// Call with `lock` held.
  func startWebListening(_ listener: AcceptListener) {
    webListener = listener
    webGeneration += 1
    let generation = webGeneration
    runningWebAcceptLoops += 1
    BlockingWork.detachThread(name: "com.openjoystickdriver.endpoint.web-accept") {
      [weak self] in
      guard let self else {
        listener.finish()
        return
      }
      self.acceptWebConnections(listener, generation: generation)
    }
  }

  /// Call with `lock` held; open web connections stay open.
  func stopWebListening() {
    guard let stopped = webListener else { return }
    // `wake` frees the address at once; the loop closes the descriptor when it wakes, so the
    // number stays taken until then.
    stopped.wake()
    webListener = nil
    webGeneration += 1
  }

  // MARK: - Private

  /// Owns the listener: waits on it and on its wake pipe, and closes it when it ends.
  ///
  /// The descriptor stays open until then, so its number cannot belong to a later listener. A
  /// connection accepted after the listener was replaced is dropped.
  private func acceptWebConnections(_ listener: AcceptListener, generation: Int) {
    defer {
      listener.finish()
      lock.withLock { runningWebAcceptLoops -= 1 }
    }
    while lock.withLock({ webGeneration == generation }) {
      beforeAcceptWait?(.web, generation)
      switch listener.wait() {
      case .woken: return
      case .failed(let code):
        print("[EndpointServer] WebSocket accept loop ends: poll failed with errno \(code)")
        return
      case .ready: break
      }
      guard let accepted = listener.accept() else {
        // EAGAIN: the pending connection was dropped between poll and accept; wait again.
        // Running out of descriptors or memory is reported and retried after a wait that
        // `stop` ends.
        let code = errno
        // A stop wakes the loop and replaces the socket under the descriptor, so the failure
        // that follows is the stop, not a fault.
        guard lock.withLock({ webGeneration == generation }) else { return }
        guard
          AcceptFailure.continuesAfter(
            errno: code,
            server: "EndpointServer",
            wake: listener.wakeRead,
            waitMilliseconds: resourceWaitMilliseconds,
            report: report
          )
        else { return }
        continue
      }
      guard lock.withLock({ webGeneration == generation }) else {
        Darwin.close(accepted)
        return
      }
      var noSignal: Int32 = 1
      setsockopt(accepted, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
      let admitted = lock.withLock { () -> Bool in
        guard pendingWebRequests < Self.maximumPendingWebRequests else { return false }
        pendingWebRequests += 1
        return true
      }
      guard admitted else {
        Darwin.close(accepted)
        continue
      }
      BlockingWork.detach(label: "com.openjoystickdriver.endpoint.web-connection") {
        [weak self] in
        guard let self else {
          Darwin.close(accepted)
          return
        }
        self.serveWeb(accepted, port: listener.port)
      }
    }
  }

  /// Answers the request on `descriptor`, then serves the endpoint on it when it upgraded.
  private func serveWeb(_ descriptor: Int32, port: Int) {
    let upgrade = answer(descriptor, port: port)
    lock.withLock { pendingWebRequests -= 1 }
    guard let upgrade else {
      shutdown(descriptor, SHUT_RDWR)
      Darwin.close(descriptor)
      return
    }
    serve(
      EndpointConnection(
        descriptor: descriptor,
        kind: .web,
        transport: EndpointWebSocketTransport(descriptor: descriptor, buffered: upgrade.rest)
      ),
      origin: upgrade.origin,
      port: port
    )
  }

  /// Answers one request within the handshake time; returns the upgrade when the request
  /// upgraded to a WebSocket.
  private func answer(_ descriptor: Int32, port: Int) -> WebUpgrade? {
    let deadline = Date().addingTimeInterval(TimeInterval(Self.handshakeSeconds))
    switch EndpointWebRequest.read(descriptor, until: deadline) {
    case .closed: return nil
    case .malformed:
      EndpointWebResponse.send(descriptor, status: 400)
      return nil
    case .request(let request, let rest):
      guard request.isAddressed(toPort: port) else {
        EndpointWebResponse.send(descriptor, status: 403)
        return nil
      }
      guard request.path == "/endpoint" else {
        servePage(request, descriptor: descriptor)
        return nil
      }
      return upgrade(request, rest: rest, descriptor: descriptor)
    }
  }

  /// Answers `101` to an upgrade from an origin that some token is granted for, or without
  /// `Origin` when some token has no origins; refuses any other request.
  ///
  /// Browsers always send `Origin`, so only a native client, such as a sandboxed app that cannot
  /// reach the socket, upgrades without one.
  private func upgrade(
    _ request: EndpointWebRequest,
    rest: Data,
    descriptor: Int32
  ) -> WebUpgrade? {
    let tokens = lock.withLock { (try? store.load())?.tokens ?? [] }
    let header = request.headers["origin"]
    let origin = header.flatMap(AccessTokenGrant.normalizedOrigin)
    let granted =
      if header == nil { tokens.contains { $0.origins.isEmpty } } else {
        origin.map { origin in tokens.contains { $0.origins.contains(origin) } } ?? false
      }
    guard granted else {
      EndpointWebResponse.send(descriptor, status: 403)
      return nil
    }
    guard request.method == "GET", request.lists("websocket", in: "upgrade"),
      request.lists("upgrade", in: "connection"),
      let key = request.headers["sec-websocket-key"], Data(base64Encoded: key)?.count == 16
    else {
      EndpointWebResponse.send(descriptor, status: 400)
      return nil
    }
    guard request.headers["sec-websocket-version"] == "13" else {
      EndpointWebResponse.send(descriptor, status: 426, headers: [("Sec-WebSocket-Version", "13")])
      return nil
    }
    let accept = Data(
      Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
    ).base64EncodedString()
    EndpointWebResponse.send(
      descriptor,
      status: 101,
      headers: [
        ("Upgrade", "websocket"), ("Connection", "Upgrade"), ("Sec-WebSocket-Accept", accept),
      ]
    )
    return WebUpgrade(origin: origin, rest: rest)
  }

  /// A request that upgraded to a WebSocket: its normalized `Origin`, nil when it sent none, and
  /// the bytes after it.
  private struct WebUpgrade {
    /// The `Origin` header, normalized; nil when the request sent none.
    let origin: String?
    /// The bytes that arrived after the request head.
    let rest: Data
  }

  /// Serves a file from the overlay pages folder to a top-level or same-origin request.
  private func servePage(_ request: EndpointWebRequest, descriptor: Int32) {
    guard ["GET", "HEAD"].contains(request.method) else {
      EndpointWebResponse.send(descriptor, status: 405, headers: [("Allow", "GET, HEAD")])
      return
    }
    if let site = request.headers["sec-fetch-site"], !["same-origin", "none"].contains(site) {
      EndpointWebResponse.send(descriptor, status: 403)
      return
    }
    guard let path = EndpointWebPages.file(for: request.path, root: store.pagesDirectory.path),
      let body = FileManager.default.contents(atPath: path)
    else {
      EndpointWebResponse.send(descriptor, status: 404)
      return
    }
    EndpointWebResponse.send(
      descriptor,
      status: 200,
      headers: [
        ("Content-Type", EndpointWebPages.contentType(of: path)),
        ("Cross-Origin-Resource-Policy", "same-origin"),
      ],
      body: body,
      includeBody: request.method == "GET"
    )
  }
}
