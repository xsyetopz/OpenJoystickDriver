import Foundation

extension DevicePipeline {
  /// Sends packets on the driver's ``USBCommandChannel`` of a controller bound over HID, reading
  /// one reply after each into the driver. The channel opens on first use and stays open until the
  /// pipeline stops or a write fails. Callers serialize this through the interface's output queue.
  func sendUSBCommands(
    _ packets: [PhysicalUSBOutputPacket],
    intervalNanoseconds: UInt64
  ) async -> Bool {
    // macOS owns a native controller's output, so an observe-only pipeline sends no commands.
    guard isActive, !observesOnly, let channel = plan.usbCommandChannel,
      let session = await openUSBCommandSession(channel)
    else { return false }
    for (index, packet) in packets.enumerated() {
      if index > 0, intervalNanoseconds > 0 {
        do { try await Task.sleep(nanoseconds: intervalNanoseconds) } catch { return false }
      }
      guard isActive, usbCommandSession === session else { return false }
      do {
        _ = try await session.write(
          endpoint: packet.endpoint,
          data: packet.bytes,
          timeout: packet.timeoutMilliseconds
        )
      } catch {
        print("[DevicePipeline] USB command failed for \(identifier): \(error)")
        await closeUSBCommandSession(session)
        return false
      }
      appendToPacketLog(bytes: packet.bytes, direction: .transmitted)
      let reply = await readUSBCommandReply(session, channel: channel)
      guard isActive, usbCommandSession === session else { return false }
      if !reply.isEmpty {
        appendToPacketLog(bytes: reply, direction: .received)
        driver.consumeUSBCommandReply(reply)
      }
    }
    return true
  }

  func closeUSBCommandSession(_ session: (any USBTransportSession)? = nil) async {
    guard let current = usbCommandSession, session.map({ $0 === current }) ?? true else { return }
    usbCommandSession = nil
    await current.close()
  }

  private func openUSBCommandSession(
    _ channel: USBCommandChannel
  ) async -> (any USBTransportSession)? {
    if let usbCommandSession { return usbCommandSession }
    guard case .hid(let locationID) = transport, let provider = usbTransportProvider else {
      return nil
    }
    let identity = identifier.controllerIdentity
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 0,
      vendorID: identity.vendorID,
      productID: identity.productID,
      locationID: locationID
    )
    let session: any USBTransportSession
    do {
      session = try await provider.open(
        device,
        options: USBTransportOpenOptions(interfaceNumber: channel.interfaceNumber)
      )
    } catch {
      print("[DevicePipeline] USB command channel open failed for \(identifier): \(error)")
      return nil
    }
    // The pipeline may have stopped, or another open finished, while this one was suspended.
    guard isActive, usbCommandSession == nil else {
      await session.close()
      return isActive ? usbCommandSession : nil
    }
    usbCommandSession = session
    return session
  }

  /// Reads up to `replyLength` bytes in max-packet chunks, ending at a short transfer. A failed
  /// read ends the reply: a command need not answer.
  private func readUSBCommandReply(
    _ session: any USBTransportSession,
    channel: USBCommandChannel
  ) async -> [UInt8] {
    var reply: [UInt8] = []
    while reply.count < channel.replyLength {
      let length = min(64, channel.replyLength - reply.count)
      guard
        let chunk = try? await session.read(
          endpoint: channel.inEndpoint,
          length: length,
          timeout: channel.replyTimeoutMilliseconds
        )
      else { break }
      reply += chunk
      if chunk.count < length { break }
    }
    return reply
  }
}
